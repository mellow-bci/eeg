#!/usr/bin/env python3
"""Independent-reader compatibility probe. Synthetic format fixtures, not an exporter.

Run in an isolated environment with edfio and pyedflib, passing a NEW output
folder. No headset data, application library or vendor software is accessed.
"""
import hashlib
import importlib.metadata
import json
from pathlib import Path
import platform
import struct
import sys
import warnings


def field(value, width):
    data = str(value).encode('ascii')
    assert len(data) <= width and all(32 <= b <= 126 for b in data)
    return data.ljust(width, b' ')


def fixture(reserved, duration, onsets):
    fixed = [(0,8), ('X X X X',80), ('Startdate 15-SEP-2026 X X X',80),
             ('15.09.26',8), ('12.00.00',8), (768,8), (reserved,44),
             (3,8), (duration,8), (2,4)]
    signals = [(['EEG AF3','EDF Annotations'],16), (['',''],80),
               (['',''],8), ([0,-1],8), ([65535,1],8),
               ([-32768,-32768],8), ([32767,32767],8),
               (['',''],80), ([1,32],8), (['',''],32)]
    header = b''.join(field(v,n) for v,n in fixed)
    header += b''.join(field(v,n) for values,n in signals for v in values)
    assert len(header) == 768
    records = []
    for raw, onset in zip([-32768,0,32767], onsets):
        annotation = (onset + '\x14\x14\x00').encode('ascii')
        assert len(annotation) <= 64
        records.append(struct.pack('<h',raw) + annotation.ljust(64,b'\x00'))
    return header + b''.join(records)


def read_edfio(path):
    import edfio
    obj = edfio.read_edf(path)
    return {'digital_samples': obj.signals[0].digital.tolist(),
            'physical_samples': obj.signals[0].data.tolist(),
            'data_record_duration': obj.data_record_duration, 'reported_duration_seconds': obj.duration}


def read_pyedflib(path):
    import pyedflib
    with pyedflib.EdfReader(str(path)) as obj:
        return {'digital_samples': obj.readSignal(0,digital=True).tolist(),
                'physical_samples': obj.readSignal(0).tolist(),
                'data_record_duration': obj.datarecord_duration, 'reported_duration_seconds': obj.file_duration}


def main():
    output = Path(sys.argv[1]); output.mkdir(parents=True,exist_ok=False)
    cases = [('continuous_control','EDF+C','1',['+0','+1','+2']),
             ('discontinuous_positive_duration','EDF+D','1',['+0','+2','+4']),
             ('zero_duration_unique_receipts','EDF+D','0',['+0','+0.01','+2']),
             ('zero_duration_repeated_receipts','EDF+D','0',['+0','+0','+2']),
             ('nominal_128hz_single_sample_records','EDF+C','.0078125',
              ['+0','+0.0078125','+0.015625'])]
    report = {'schema':'eeg.edf-reader-probe.v1','synthetic':True,
              'python':platform.python_version(), 'platform':platform.platform(),
              'versions':{name:importlib.metadata.version(name) for name in ['edfio','pyedflib','numpy']},
              'cases':[], 'timestamp_roundtrip_qualified':False,
              'limitations':['Hand-built minimal fixtures, not native exporter output',
                'Successful loading alone is not preservation of per-record timing',
                'No hardware, physiological or full EDF compliance qualification']}
    for name,reserved,duration,onsets in cases:
        data=fixture(reserved,duration,onsets); path=output/(name+'.edf');path.write_bytes(data)
        row={'name':name,'sha256':hashlib.sha256(data).hexdigest(),
             'record_onsets_seconds':onsets,'record_duration_seconds':duration,
             'last_record_end_seconds':float(onsets[-1])+float(duration),'readers':{}}
        for reader, load in [('edfio',read_edfio),('pyedflib',read_pyedflib)]:
            with warnings.catch_warnings(record=True) as notices:
                warnings.simplefilter('always')
                try:
                    result=load(path)
                    result.update(accepted=True, digital_exact=result['digital_samples']==[-32768,0,32767],
                                  physical_exact=result['physical_samples']==[0,32768,65535])
                except Exception as error:
                    result={'accepted':False,'error_type':type(error).__name__,'error':str(error).replace(str(output),'OUTPUT')}
                result['warnings']=[str(n.message) for n in notices]
                row['readers'][reader]=result
        report['cases'].append(row)
    (output/'report.json').write_text(json.dumps(report,indent=2,allow_nan=False)+'\n')
    control=report['cases'][0]['readers']
    assert all(r['accepted'] and r['digital_exact'] and r['physical_exact'] for r in control.values()), 'Continuous control failed; do not interpret candidate results as compatibility evidence'
    nominal = report['cases'][-1]['readers']
    assert all(r['accepted'] and r['digital_exact'] and r['physical_exact']
               and r['data_record_duration'] == 1 / 128
               and r['reported_duration_seconds'] == 3 / 128
               for r in nominal.values()), 'Nominal 128 Hz fixture roundtrip failed'
    print(json.dumps(report,indent=2,allow_nan=False))


if __name__=='__main__':
    main()
