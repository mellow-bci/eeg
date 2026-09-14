"""Descriptive comparison of operator-cued phases; no physiological verdict."""
import json,sys
from pathlib import Path
import numpy as np
from scipy.signal import welch
p=Path(sys.argv[1]);rows=[json.loads(l) for l in p.read_text().splitlines()]
marks=[json.loads(l) for l in p.with_suffix('.markers.jsonl').read_text().splitlines()]
results={}
for a,b in zip(marks,marks[1:]):
 lo=a['latest_sample_host_time']+5;hi=b['latest_sample_host_time']-3
 mid=(lo+hi)/2;lo=max(lo,mid-10);hi=min(hi,mid+10)
 samples=[r for r in rows if r['kind']=='eeg_adc' and lo<=r['received_at']<hi]
 ok=bool(samples) and all(s.get('continuous') and s.get('transport_stable') for s in samples)
 ok=ok and len({s['epoch'] for s in samples})==1
 ok=ok and all(y['stream_index']==x['stream_index']+1 for x,y in zip(samples,samples[1:]))
 phase={'start':lo,'end':hi,'samples':len(samples),'contiguous_stable':ok,'channels':{}}
 if ok and len(samples)>=1024:
  for name in samples[0]['electrodes_microvolts']:
   x=np.array([s['electrodes_microvolts'][name] for s in samples]);f,psd=welch(x,fs=128,nperseg=512,detrend='linear')
   def power(l,h):return float(psd[(f>=l)&(f<h)].sum()*(f[1]-f[0]))
   total=power(1,40);band=power(8,13)
   phase['channels'][name]={'power_8_13_uV2':band,'power_1_40_uV2':total,'fraction_8_13':band/total if total else None,'adc_rail_fraction':float(np.mean((x==0)|(x==65535/7.8)))}
 results[a['phase']]=phase
out={'source':str(p),'phase_cues_verified_by_sensor':False,'physiology_validated':False,'phases':results}
p.with_suffix('.phase-analysis.json').write_text(json.dumps(out,indent=2))
for name in ('O1','O2','AF3','AF4'):
 print(name,{k:{m:round(v['channels'].get(name,{}).get(m,float('nan')),3) for m in ('power_8_13_uV2','fraction_8_13')} for k,v in results.items()})
print('phases',[(k,v['samples'],v['contiguous_stable']) for k,v in results.items()])
