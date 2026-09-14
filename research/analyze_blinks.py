"""Descriptive cue-locked response; no blink classification or EEG validation."""
import json, sys
from pathlib import Path
import numpy as np
from scipy.signal import detrend
p=Path(sys.argv[1]); rows=[json.loads(l) for l in p.read_text().splitlines()]
samples=[r for r in rows if r['kind']=='eeg_adc']
cues=[r for r in rows if r['kind']=='phase_cue_onset' and r['phase'].startswith('blink_')]
def window(lo,hi):
 s=[r for r in samples if lo<=r['received_at']<hi]
 valid=len(s)>=256 and all(r.get('transport_stable') and r.get('continuous') for r in s) and len({r['epoch'] for r in s})==1 and all(b['stream_index']==a['stream_index']+1 for a,b in zip(s,s[1:]))
 result={'samples':len(s),'valid':valid,'channels':{}}
 if valid:
  for ch in s[0].get('electrodes_microvolts',{}):
   x=detrend([r['electrodes_microvolts'][ch] for r in s])
   result['channels'][ch]={'detrended_rms_uV':float(np.sqrt(np.mean(x*x))),'detrended_ptp_uV':float(np.ptp(x))}
 return result
out={'source':str(p),'physiology_validated':False,'actual_blinks_measured':False,'method':'Equal 4-second pre-cue and post-cue windows; linear detrend only. Speech may cause responses; timing is software cue onset. No classifier threshold.','trials':[]}
for cue in cues:
 t=cue['t'];pre=window(t-4,t);post=window(t,t+4)
 trial={'phase':cue['phase'],'cue_onset':t,'pre':pre,'post':post}
 out['trials'].append(trial)
 print(cue['phase'], 'valid',pre['valid'],post['valid'], {ch:round(post['channels'][ch]['detrended_rms_uV']/max(pre['channels'][ch]['detrended_rms_uV'],1e-9),2) for ch in ('AF3','AF4','O1','O2') if ch in pre['channels'] and ch in post['channels']})
p.with_suffix('.blink-analysis.json').write_text(json.dumps(out,indent=2))
