"""Offline, session-held-out evaluation of labeled EEG experiments. Never emits actions.

Supports eyes-open/closed spectral features and deliberate-blink/neutral artifact
features. Neither target is a cognitive state score or a general mental command.
"""
import argparse, hashlib, json, math, os
from pathlib import Path
import numpy as np
from scipy.signal import detrend, welch

LABELS={'eyes':['eyes_open','eyes_closed'],'blink':['neutral','deliberate_blink']}


def read_capture(path):
    result=[]
    with Path(path).open() as f:
        for line in f:
            if not line.endswith('\n'):raise ValueError('Incomplete recording')
            row=json.loads(line)
            if row.get('kind')=='eeg_adc':result.append(row)
    return result



def eeg_content_sha256(rows):
    """Fingerprint ordered measured values independent of timestamps/JSON formatting.

    This blocks reuse of a complete capture under another filename or metadata.
    It does not prove independently acquired sessions or detect every partial reuse.
    """
    if not rows:raise ValueError('Recording contains no EEG samples')
    digest=hashlib.sha256()
    for row in rows:
        if 'adc_words' in row:
            field='adc_words';values=row[field]
            if not isinstance(values,list) or not values:raise ValueError('Invalid EEG values')
            payload=[float(v) for v in values]
        else:
            field='electrodes_adc' if 'electrodes_adc' in row else 'electrodes_microvolts'
            values=row.get(field)
            if not isinstance(values,dict) or not values:raise ValueError('Invalid EEG values')
            payload={str(k):float(v) for k,v in sorted(values.items())}
        digest.update(json.dumps([field,payload],sort_keys=True,separators=(',',':'),allow_nan=False).encode())
        digest.update(b'\n')
    return digest.hexdigest()


def features(samples,start,end,protocol):
    if not math.isfinite(start) or not math.isfinite(end) or end-start<4:raise ValueError('Trial requires at least four finite seconds')
    rows=[r for r in samples if start<=r['received_at']<end]
    if len(rows)<512:raise ValueError('Trial has fewer than 512 samples')
    if any(not r.get('transport_stable') or not r.get('continuous') for r in rows):raise ValueError('Trial is not transport-stable')
    if len({(r.get('epoch'),r.get('stable_segment')) for r in rows})!=1:raise ValueError('Trial crosses a connection/segment boundary')
    if any(b['stream_index']!=a['stream_index']+1 for a,b in zip(rows,rows[1:])):raise ValueError('Trial has missing samples')
    span=rows[-1]['received_at']-rows[0]['received_at']
    if span<=0 or not 120<=(len(rows)-2)/span<=136:raise ValueError('Observed sample rate is incompatible with 128 Hz analysis')
    channels=('O1','O2') if protocol=='eyes' else ('AF3','AF4')
    values=[]
    for channel in channels:
        try:x=np.array([r['electrodes_microvolts'][channel] for r in rows],dtype=float)
        except KeyError:raise ValueError('Vendor-equivalent voltage configuration is required')
        if not np.isfinite(x).all() or np.any((x<=0)|(x>=65535/7.8)):raise ValueError('Invalid or rail-clipped voltage')
        if protocol=='eyes':
            f,p=welch(x,fs=128,nperseg=512,detrend='linear')
            total=p[(f>=1)&(f<40)].sum()
            if total<=0:raise ValueError('Flat signal')
            values.append(float(p[(f>=8)&(f<13)].sum()/total))
        else:
            rms=np.sqrt(np.mean(detrend(x)**2))
            if rms<=0:raise ValueError('Flat signal')
            values.append(float(np.log(rms)))
    return values


def wilson(successes,total):
    if not total:return None
    z=1.95996398454;p=successes/total;d=1+z*z/total
    center=(p+z*z/(2*total))/d;half=z*math.sqrt(p*(1-p)/total+z*z/(4*total*total))/d
    return [0.0 if successes==0 else max(0,center-half),1.0 if successes==total else min(1,center+half)]


def fit_lda(x,y):
    x=np.asarray(x,dtype=float);y=np.asarray(y)
    if x.ndim!=2 or not np.isfinite(x).all() or set(y)!={0,1}:raise ValueError('Both classes and finite features are required')
    mean=x.mean(axis=0);scale=x.std(axis=0);scale[scale<1e-12]=1
    z=(x-mean)/scale;m0=z[y==0].mean(axis=0);m1=z[y==1].mean(axis=0)
    residual=np.vstack([z[y==0]-m0,z[y==1]-m1]);cov=residual.T@residual/max(1,len(x)-2)+np.eye(x.shape[1])*0.1
    weight=np.linalg.solve(cov,m1-m0);bias=-.5*float((m1+m0)@weight)
    return {'mean':mean.tolist(),'scale':scale.tolist(),'weight':weight.tolist(),'bias':bias,'regularization':0.1,'class_prior':'equal'}


def predict(model,x):
    z=(np.asarray(x)-model['mean'])/model['scale']
    return (z@model['weight']+model['bias']>=0).astype(int)


def evaluate(manifest,base=Path('.')):
    protocol=manifest.get('protocol')
    if protocol not in LABELS:raise ValueError('protocol must be eyes or blink')
    sessions=manifest.get('sessions',[]);ids=set();hashes=set();content_hashes=set();groups={'train':[],'test':[]};trials={'train':[],'test':[]};provenance=[]
    participants={s.get('participant_id') for s in sessions}
    if len(participants)!=1 or None in participants:raise ValueError('This calibration must use one explicit participant ID')
    for session in sessions:
        sid=session['session_id'];split=session['split']
        if not isinstance(sid,str) or not sid or sid in ids:raise ValueError('Unique session IDs required')
        if split not in groups:raise ValueError('Every session is assigned train or test, never individual windows')
        ids.add(sid);path=(Path(base)/session['recording']).resolve();digest=hashlib.sha256(path.read_bytes()).hexdigest()
        if digest in hashes:raise ValueError('Recording reused across sessions: data leakage')
        hashes.add(digest);groups[split].append(sid);rows=read_capture(path);content_digest=eeg_content_sha256(rows)
        if content_digest in content_hashes:raise ValueError('EEG content reused across sessions: data leakage')
        content_hashes.add(content_digest);intervals=[];seen_trials=set()
        if session.get('labels_verified') is not True:raise ValueError('Participant trial compliance must be explicitly verified; cue text alone is not ground truth')
        for trial in session['trials']:
            tid=trial['trial_id'];label=trial['label'];start=float(trial['start']);end=float(trial['end'])
            if tid in seen_trials:raise ValueError('Duplicate trial ID')
            seen_trials.add(tid)
            if label not in LABELS[protocol]:raise ValueError('Unsupported trial label')
            if any(start<b and end>a for a,b in intervals):raise ValueError('Overlapping trials are not independent')
            intervals.append((start,end))
            vector=features(rows,start,end,protocol)
            trials[split].append({'session_id':sid,'trial_id':tid,'label':LABELS[protocol].index(label),'features':vector,'seconds':end-start})
        provenance.append({'session_id':sid,'split':split,'sha256':digest,'eeg_content_sha256':content_digest,'trials':len(intervals)})
    if len(groups['train'])<2 or len(groups['test'])<1:raise ValueError('Require at least two training sessions and one independent test session')
    for split in trials:
        for label in (0,1):
            if sum(t['label']==label for t in trials[split])<10:raise ValueError('Require at least ten trials per class in each split')
    train=trials['train'];test=trials['test'];model=fit_lda([t['features'] for t in train],[t['label'] for t in train]);y=np.array([t['label'] for t in test]);out=predict(model,[t['features'] for t in test])
    cm=[[int(np.sum((y==actual)&(out==pred))) for pred in (0,1)] for actual in (0,1)]
    correct=int(np.sum(out==y));n=len(y);negative=int(np.sum(y==0));false=int(np.sum((y==0)&(out==1)))
    return {'schema_version':'eeg.calibration.evaluation.v1','protocol':protocol,'classes':LABELS[protocol],
        'method':'Two predeclared channel features; training-only standardization; regularized equal-prior LDA; whole-session holdout',
        'provenance':provenance,'model':model,'test_trials':n,'confusion_matrix_actual_rows':cm,'accuracy':correct/n,
        'accuracy_wilson_95':wilson(correct,n),'negative_trials':negative,'false_positive_trials':false,
        'false_positive_trial_fraction':false/negative,'false_positive_wilson_95':wilson(false,negative),
        'trial_predictions':[dict(t,prediction=int(p)) for t,p in zip(test,out)],
        'cognitive_score_validated':False,'mental_command_validated':False,'system_control_enabled':False,
        'limitations':['Trial labels are operator declarations, not independently sensed ground truth.',
            'Distinct file and EEG-content hashes reject full-record reuse but cannot prove independent acquisition or exclude all partial overlap.',
            'Held-out trial accuracy does not establish continuous neutral false-activation rate.',
            'Eyes target is sensory state; blink target is an ocular gesture, not general neural intent.',
            'No production pass threshold or accessibility output is enabled by this report.']}


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('manifest');p.add_argument('--output',required=True);a=p.parse_args()
    source=Path(a.manifest);report=evaluate(json.loads(source.read_text()),source.parent)
    with os.fdopen(os.open(a.output,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600),'w') as f:json.dump(report,f,indent=2);f.write('\n')
    print('Held-out evaluation written. No system-control capability enabled.')
if __name__=='__main__':main()
