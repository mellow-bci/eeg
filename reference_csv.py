"""Validate an official EmotivPRO V2 EEG/CQ CSV for later comparison.

No matching based on wrapping counters alone; no automatic validation verdict.
https://emotiv.gitbook.io/emotivpro-v3/managing-your-eeg-data-recordings/exporting-an-eeg-data-recording/csv-files
"""
import argparse,csv,hashlib,json,math
from pathlib import Path
from contact_quality import CQ_ELECTRODES

def inspect(path):
    path=Path(path)
    with path.open(encoding='utf-8-sig',newline='') as stream:
        metadata=next(csv.reader(stream),None)
        if not metadata:raise ValueError('Missing export metadata')
        meta={}
        for field in metadata:
            if ':' in field:
                k,v=field.split(':',1);meta[k.strip().lower()]=v.strip()
        for k in ('headset serial','sampling rate'):
            if not meta.get(k):raise ValueError('Missing metadata: '+k)
        rate=float(meta['sampling rate'])
        if rate!=128:raise ValueError('Only the observed 128 Hz comparison is supported')
        reader=csv.DictReader(stream)
        columns=reader.fieldnames or []
        if len(columns)!=len(set(columns)):raise ValueError('Duplicate column names')
        required=['Timestamp','EEG.Counter','EEG.Interpolated']+['EEG.'+c for c in CQ_ELECTRODES]+['CQ.'+c for c in CQ_ELECTRODES]
        missing=set(required)-set(columns)
        if missing:raise ValueError('Missing EEG/CQ columns: '+', '.join(sorted(missing)))
        count=interpolated=gaps=0;previous=None;first=last=None
        for row in reader:
            if None in row:raise ValueError('Too many fields in data row')
            def number(k):
                value=float(row[k])
                if not math.isfinite(value):raise ValueError('Non-finite value: '+k)
                return value
            timestamp=number('Timestamp');counter=number('EEG.Counter');interp=number('EEG.Interpolated')
            if not counter.is_integer() or not 0<=counter<128:raise ValueError('Invalid sample counter')
            if interp<0 or not interp.is_integer():raise ValueError('Invalid interpolation marker')
            if last is not None and timestamp<=last:raise ValueError('Non-increasing sample timestamps')
            if previous is not None and counter!=(previous+1)%128:gaps+=1
            for c in CQ_ELECTRODES:
                number('EEG.'+c);quality=number('CQ.'+c)
                if not quality.is_integer() or not 0<=quality<=4:raise ValueError('Invalid contact quality')
            count+=1;interpolated+=int(interp>0);previous=counter
            if first is None:first=timestamp
            last=timestamp
        if count==0:raise ValueError('No EEG samples')
    return {'source':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
            'metadata':meta,'samples':count,'interpolated_samples':interpolated,
            'counter_discontinuities':gaps,'first_timestamp':first,'last_timestamp':last,
            'has_raw_cq':'EEG.RawCq' in columns,'channels':list(CQ_ELECTRODES),
            'format_checked':True,'same_samples_verified':False,'decoder_validated':False,
            'remaining':'Verify headset/configuration and common acquisition provenance before sample matching; preserve processing settings.'}
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('csv');p.add_argument('--output',required=True);args=p.parse_args()
    result=inspect(args.csv)
    with Path(args.output).open('x') as out:json.dump(result,out,indent=2)
    print(json.dumps({k:result[k] for k in ('samples','interpolated_samples','counter_discontinuities','decoder_validated')}))
