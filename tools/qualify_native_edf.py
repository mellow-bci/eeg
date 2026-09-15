#!/usr/bin/env python3
"""Read native synthetic exporter output with two independent EDF libraries.

No vendor runtime or headset access. Input must include the optional XCTest
qualification-input.json; this tool does not generate EDF or rewrite timestamps.
"""
import datetime
from decimal import Decimal
import hashlib
import importlib.metadata
import json
from pathlib import Path
import platform
import sys
import tempfile
import warnings

import edfio
import numpy as np
import pyedflib


def timekeeping(path):
    """Independent fixed-header/TAL inspection using decimal arithmetic."""
    data = path.read_bytes()
    header_size, records, signals = int(data[184:192]), int(data[236:244]), int(data[252:256])
    labels = [data[256 + 16 * i:256 + 16 * (i + 1)].decode('ascii').strip() for i in range(signals)]
    sizes = [int(data[256 + 216 * signals + 8 * i:256 + 216 * signals + 8 * (i + 1)]) for i in range(signals)]
    annotation = labels.index('EDF Annotations')
    offset, stride = 2 * sum(sizes[:annotation]), 2 * sum(sizes)
    assert len(data) == header_size + records * stride
    onsets = []
    for i in range(records):
        start = header_size + i * stride + offset
        tal = data[start:start + 2 * sizes[annotation]]
        onsets.append(Decimal(tal.split(b'\x14', 1)[0].decode('ascii')))
    assert onsets and all(b - a == Decimal(1) / 128 for a, b in zip(onsets, onsets[1:])), 'Nominal record onsets are not contiguous at 128 Hz'
    return onsets


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
        onsets = timekeeping(path)
        assert len(onsets) == count
        # Negative control: a temporary copy with one onset digit changed must
        # fail the independent interval check. Never edit the native artifact.
        assert len(onsets) >= 2, 'Qualification fixture needs at least two records'
        needle = ('+' + str(onsets[1]) + '\x14').encode('ascii')
        modified = bytearray(path.read_bytes())
        position = modified.find(needle)
        assert position >= 0
        modified[position + 1] = ord('8') if modified[position + 1] == ord('9') else ord('9')
        rejected = False
        with tempfile.TemporaryDirectory() as temporary:
            altered = Path(temporary) / 'altered.edf'
            altered.write_bytes(modified)
            try:
                timekeeping(altered)
            except AssertionError:
                rejected = True
        assert rejected, 'Changed onset was not detected'
        result = {'file': item['file'], 'sha256': digest, 'sample_count': count,
                  'expected_local_nominal_start': expected_date.isoformat(),
                  'first_tal_onset_seconds': str(onsets[0]), 'last_tal_onset_seconds': str(onsets[-1]),
                  'all_tal_intervals_exact_128hz': True, 'altered_onset_rejected': rejected, 'readers': {}}
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
                    low_level_start = None
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
                        # Tagged v0.1.42 edflib.h specifies 100 ns ticks; the
                        # Cython property exposes hdr.starttime_subsecond directly.
                        base = datetime.datetime(obj.startdate_year, obj.startdate_month, obj.startdate_day,
                                                 obj.starttime_hour, obj.starttime_minute, obj.starttime_second)
                        low_level_start = base + datetime.timedelta(microseconds=subsecond / 10)
                        annotation_onsets, _, texts = obj.readAnnotations()
                        annotations = list(zip(annotation_onsets.tolist(), texts.tolist()))
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
                if low_level_start is not None:
                    low_error = (low_level_start - expected_date).total_seconds()
                    row.update(raw_tick_unit_seconds='0.0000001',
                               raw_ticks_match_first_tal=subsecond == int(onsets[0] * 10_000_000),
                               low_level_local_start=low_level_start.isoformat(),
                               low_level_start_error_seconds=low_error,
                               low_level_start_within_one_microsecond=abs(low_error) <= 1e-6)
        report['segments'].append(result)
    assert cursor == len(truth['raw_samples'])
    report['all_start_times_qualified'] = all(r['start_within_one_microsecond'] for s in report['segments'] for r in s['readers'].values())
    report['all_low_level_starts_qualified'] = all(
        s['readers']['edfio']['start_within_one_microsecond']
        and s['readers']['pyedflib']['raw_ticks_match_first_tal']
        and s['readers']['pyedflib']['low_level_start_within_one_microsecond'] for s in report['segments'])
    print(json.dumps(report, indent=2, allow_nan=False))
    # A known datetime discrepancy must be reported, never hidden by relaxing
    # sample checks or compensating for one reader in the writer.
    checks = ['digital_exact', 'physical_raw_exact', 'channel_order_exact', 'uncalibrated_dimensions',
              'sample_rates_exact', 'duration_exact', 'nominal_notice_exact']
    assert all(all(r[k] for k in checks) for s in report['segments'] for r in s['readers'].values()), 'Native numeric/annotation roundtrip failed'
    assert report['all_low_level_starts_qualified'], 'Reader raw timestamp or nominal start roundtrip failed'


if __name__ == '__main__':
    main()
