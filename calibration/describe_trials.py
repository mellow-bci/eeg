"""Describe actual cued trials without claiming classifier validation."""
import argparse, hashlib, json, os
from pathlib import Path
import numpy as np
from calibration.evaluate import features,read_capture

def describe(path):
    rows=[]
    with Path(path).open() as f:
        for line in f:rows.append(json.loads(line))
    starts={};trials=[];samples=[r for r in rows if r.get('kind')=='eeg_adc']
    for row in rows:
        if row.get('kind')=='experiment_trial_start' and row.get('trial_id'):starts[row['trial_id']]=row
        if row.get('kind')=='experiment_trial_end' and row.get('trial_id') in starts:
            start=starts[row['trial_id']];label=start['label']
            if label not in ('eyes_open','eyes_closed'):continue
            trial={'trial_id':row['trial_id'],'label':label,'start':start['t']+2,'end':row['t']-.5,'compliance_verified':False}
            try:trial['features_O1_O2_alpha_fraction']=features(samples,trial['start'],trial['end'],'eyes');trial['usable']=True
            except ValueError as exc:trial['usable']=False;trial['rejected_reason']=str(exc)
            trials.append(trial)
    groups={}
    for label in ('eyes_open','eyes_closed'):
        vectors=[t['features_O1_O2_alpha_fraction'] for t in trials if t['label']==label and t['usable']]
        groups[label]={'usable_trials':len(vectors),'median_O1_O2':np.median(vectors,axis=0).tolist() if vectors else None}
    summaries=[r for r in rows if r.get('kind')=='summary']
    return {'method':'Discard first2s and last0.5s of each actual post-speech trial. Welch512,128Hz,linear detrend,8–13Hz /1–40Hz power fraction at O1/O2.',
        'source_sha256':hashlib.sha256(Path(path).read_bytes()).hexdigest(),'experiment_complete':any(r.get('kind')=='experiment_complete' for r in rows),
        'recording_summary':summaries[-1] if summaries else None,'trials':trials,'condition_summary':groups,
        'participant_compliance_verified':False,'cognitive_score_validated':False,'mental_command_validated':False,'system_control_enabled':False,
        'interpretation':'Descriptive cued sensory-state experiment only. No held-out sessions or independently observed trial labels.'}
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('recording');p.add_argument('--output',required=True);a=p.parse_args();report=describe(a.recording)
    with os.fdopen(os.open(a.output,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600),'w') as f:json.dump(report,f,indent=2);f.write('\n')
    print(json.dumps(report['condition_summary'],indent=2))
