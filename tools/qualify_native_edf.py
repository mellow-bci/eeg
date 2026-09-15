#!/usr/bin/env python3
"""Read native synthetic exporter output with two independent EDF libraries.

No vendor runtime or headset access. Input must include the optional XCTest
qualification-input.json; this tool does not generate EDF or rewrite timestamps.
"""
import datetime
import hashlib
import importlib.metadata
import json
from pathlib import Path
import platform
import sys
import warnings

import edfio
import numpy as np
import pyedflib


def main():
    root = Path(sys.argv[1])
    truth = json.loads((root / 'qualification-input.json').read_text())
    assert truth['synthetic'] is True
    receipt = json.loads((root / 'provenance.json').read_text())
    original = root / receipt['source_file']
    assert hashlib.sha256(original.read_bytes()).hexdigest() == receipt['source_sha256']
    assert receipt['sample_count'] == len(truth['raw_samples'])
    report = {'schema': 'eeg.native-edf-reader-qualification.v1', 'synthetic': True,
              'versions': {n: importlib.metadata.version(n) for n in ['edfio', 'pyedflib', 'numpy']},
              'python': platform.python_version(), 'source_sha256': receipt['source_sha256'],
              'writer_implementation': receipt['writer_implementation'],
              'hardware_validated': False, 'segments': [],
              'scope': 'Native writer output; all raw channels/counts, nominal rate/duration, notice and start datetime. Native trial/marker translation is not implemented.'}
    cursor = 0
    for i, item in enumerate(receipt['segments']):
        path = root / item['file']
        count = truth['segment_counts'][i]
        expected = np.array(truth['raw_samples'][cursor:cursor + count]).T
        cursor += count
        selected = truth['wall_unix_seconds'] + truth['first_receipt_seconds'][i] - truth['receipt_after']
        # Header records local time; treat this as a naive civil datetime, not UTC.
        expected_date = datetime.datetime.fromtimestamp(selected + truth['utc_offset_seconds'], datetime.timezone.utc).replace(tzinfo=None)
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        assert digest == item['sha256']
        result = {'file': item['file'], 'sha256': digest, 'sample_count': count,
                  'expected_local_nominal_start': expected_date.isoformat(), 'readers': {}}
        for name in ['edfio', 'pyedflib']:
            with warnings.catch_warnings(record=True) as notices:
                warnings.simplefilter('always')
                if name == 'edfio':
                    obj = edfio.read_edf(path)
                    digital = np.array([s.digital for s in obj.signals])
                    physical = np.array([s.data for s in obj.signals])
                    rates = [s.sampling_frequency for s in obj.signals]
                    labels = [s.label for s in obj.signals]
                    dimensions = [s.physical_dimension for s in obj.signals]
                    duration = obj.duration
                    start = datetime.datetime.combine(obj.startdate, obj.starttime)
                    annotations = [(a.onset, a.text) for a in obj.annotations]
                    subsecond = None
                else:
                    with pyedflib.EdfReader(str(path)) as obj:
                        digital = np.array([obj.readSignal(c, digital=True) for c in range(obj.signals_in_file)])
                        physical = np.array([obj.readSignal(c) for c in range(obj.signals_in_file)])
                        rates = obj.getSampleFrequencies().tolist()
                        labels = obj.getSignalLabels()
                        dimensions = [obj.getPhysicalDimension(c) for c in range(obj.signals_in_file)]
                        duration = obj.file_duration
                        start = obj.getStartdatetime()
                        subsecond = obj.starttime_subsecond
                        onsets, _, texts = obj.readAnnotations()
                        annotations = list(zip(onsets.tolist(), texts.tolist()))
                error = (start - expected_date).total_seconds()
                row = {'digital_exact': np.array_equal(digital, expected - 32768),
                       'physical_raw_exact': np.array_equal(physical, expected),
                       'channel_order_exact': labels == ['EEG ' + c for c in receipt['channels']],
                       'uncalibrated_dimensions': all(d == '' for d in dimensions),
                       'sample_rates_exact': rates == [128] * 14,
                       'duration_exact': duration == count / 128,
                       'nominal_notice_exact': annotations == [(0.0, 'Derived nominal 128 Hz; see provenance.json')],
                       'local_start': start.isoformat(), 'start_error_seconds': error,
                       'start_within_one_microsecond': abs(error) <= 1e-6,
                       'raw_starttime_subsecond': subsecond,
                       'warnings': [str(n.message) for n in notices]}
                result['readers'][name] = row
        report['segments'].append(result)
    assert cursor == len(truth['raw_samples'])
    report['all_start_times_qualified'] = all(r['start_within_one_microsecond'] for s in report['segments'] for r in s['readers'].values())
    print(json.dumps(report, indent=2, allow_nan=False))
    # A known datetime discrepancy must be reported, never hidden by relaxing
    # sample checks or compensating for one reader in the writer.
    checks = ['digital_exact', 'physical_raw_exact', 'channel_order_exact', 'uncalibrated_dimensions',
              'sample_rates_exact', 'duration_exact', 'nominal_notice_exact']
    assert all(all(r[k] for k in checks) for s in report['segments'] for r in s['readers'].values()), 'Native numeric/annotation roundtrip failed'


if __name__ == '__main__':
    main()
