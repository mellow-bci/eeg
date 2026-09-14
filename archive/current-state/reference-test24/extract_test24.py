"""Extract the logged TEST24 interval from a recovered vendor device-session file."""
from pathlib import Path
from datetime import datetime
import csv,hashlib,json
import numpy as np
import pyarrow.parquet as pq
root=Path(__file__).parent
start=datetime.fromisoformat('2026-09-15T00:45:30.689355+05:30').timestamp()
end=datetime.fromisoformat('2026-09-15T00:47:20.847212+05:30').timestamp()
t=pq.read_table(root/'recovered.parquet');ts=t['Timestamp'].to_numpy();keep=(ts>=start)&(ts<=end)
cols=['Timestamp','EEG.Counter','EEG.Interpolated']+[n for n in t.column_names if n.startswith('EEG.') and n.split('.')[1] in ('AF3','F7','F3','FC5','T7','P7','O1','O2','P8','T8','FC6','F4','F8','AF4')]+['EEG.RawCq']+[n for n in t.column_names if n.startswith('CQ.')]
a={n:t[n].to_numpy()[keep] for n in cols}
with (root/'TEST24-recovered.csv').open('x',newline='') as out:
 w=csv.writer(out);w.writerow(['title:TEST24','headset serial:E50213EE','sampling rate:128','source:local encrypted device-session recovery','official export:false'])
 w.writerow(cols);w.writerows(zip(*(a[n] for n in cols)))
channels={}
for n in cols:
 if n.startswith('EEG.') and n not in ('EEG.Counter','EEG.Interpolated','EEG.RawCq'):
  x=a[n];residual=np.abs(x*7.8-np.rint(x*7.8))
  channels[n]={'min_uV':float(np.min(x)),'max_uV':float(np.max(x)), 'max_ADC_grid_residual':float(np.max(residual))}
result={'record_uuid':'4b52fc6f-8152-4a34-8a71-3bad96dc6b7b','device_session_id':'d146d8ec-d9c2-40e6-90f3-bf6162df1112',
 'interval_basis':'TEST24 start/end metadata from official application log, matched against Timestamp',
 'record_start':start,'record_end':end,'source_rows':t.num_rows,'interval_samples':int(keep.sum()),
 'first_timestamp':float(a['Timestamp'][0]),'last_timestamp':float(a['Timestamp'][-1]),
 'interpolated_samples':int(np.sum(a['EEG.Interpolated']>0)),
 'counter_discontinuities':int(np.sum((np.diff(a['EEG.Counter'])%128)!=1)),
 'channels':channels,'contact_quality_levels':{n:np.unique(a[n]).tolist() for n in cols if n.startswith('CQ.')},
 'source_sha256':hashlib.sha256((root/'source.eparquet').read_bytes()).hexdigest(),
 'recovered_sha256':hashlib.sha256((root/'recovered.parquet').read_bytes()).hexdigest(),
 'parquet_authenticated_read':True,'official_export':False,'same_samples_as_direct_BLE':False,'decoder_validated':False}
(root/'recovery-report.json').write_text(json.dumps(result,indent=2))
print(json.dumps({k:result[k] for k in ('interval_samples','interpolated_samples','counter_discontinuities','contact_quality_levels')}))
