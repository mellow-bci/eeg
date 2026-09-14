"""Synthetic oracle for native labeled evaluation; not physiological evidence."""
import hashlib,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from processing.workflow import evaluate_profile
root=Path(__file__).resolve().parents[1]
p=json.loads((root/'apple/Fixtures/spectrum/mental-profile.json').read_text())
rows=[]
for i in range(20):
 label='neutral' if i<10 else 'task'
 row={'values':[v+(0 if i<10 else 2)*s for v,s in zip(p['center'],p['scale'])],
      'feature_config_id':p['feature_config_id'],'participant_id':p['participant_id'],
      'session_id':'evaluation','continuity_id':'segment-1','window_id':f'eval:{i}',
      'start':i*2.,'end':(i+1)*2.-1/128,'label':label,'accepted':True,'label_verified':True,
      'usable':i!=1,'artifact_flags':['synthetic_artifact'] if i==1 else [],
      'recording_content_sha256':hashlib.sha256(b'evaluation').hexdigest(),
      'trial_id':label,'trial_start':0. if i<10 else 20.,'trial_end':20. if i<10 else 40.,
      'condition':'cued_neutral' if i<10 else 'cued_task','shadow_enabled':i!=2,'cue_completed_at':None}
 rows.append(row)
report=evaluate_profile(p,rows)
report.pop('processing_latency_seconds',None) # Runtime measurements are not fixture constants.
path=root/'apple/Fixtures/spectrum/mental-evaluation.json'
path.write_text(json.dumps({'records':rows,'expected':report},indent=2,allow_nan=False)+'\n')
print(path)
