"""Extract a caller-supplied interval from a recovered EEG table; not official export."""
import argparse, csv, os
from datetime import datetime
from pathlib import Path
import pyarrow.parquet as pq
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('input');p.add_argument('--start',required=True);p.add_argument('--end',required=True)
p.add_argument('--headset-serial',required=True);p.add_argument('--output',required=True)
a=p.parse_args();start=datetime.fromisoformat(a.start);end=datetime.fromisoformat(a.end)
if start.tzinfo is None or end.tzinfo is None or end<=start:raise SystemExit('Provide ordered timezone-qualified ISO times')
t=pq.read_table(a.input);ts=t['Timestamp'].to_numpy();mask=(ts>=start.timestamp())&(ts<=end.timestamp())
if not mask.any():raise SystemExit('No rows in supplied interval')
names=['Timestamp','EEG.Counter','EEG.Interpolated']
electrodes=['AF3','F7','F3','FC5','T7','P7','O1','O2','P8','T8','FC6','F4','F8','AF4']
names+=['EEG.'+n for n in electrodes]
if 'EEG.RawCq' in t.column_names:names+=['EEG.RawCq']
names+=[n for n in t.column_names if n.startswith('CQ.')]
columns=[t[n].to_numpy()[mask] for n in names]
with os.fdopen(os.open(a.output,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600),'w',newline='') as f:
 w=csv.writer(f);w.writerow(['headset serial:'+a.headset_serial,'sampling rate:128','source:local recording recovery','official export:false'])
 w.writerow(names);w.writerows(zip(*columns))
print('Recovered interval samples:',int(mask.sum()))
