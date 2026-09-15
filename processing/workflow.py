"""Canonical replay → windows → features → profile → read-only proposals.

One processing path for Python-reference and native recordings. No OS actions.
"""
import argparse,hashlib,json,os,time,tempfile,re
from contextlib import contextmanager
from pathlib import Path
import numpy as np
from processing.contract import iter_samples
from processing.windows import iter_windows
from processing.features import extract_matrix,CONFIG_ID
from processing.mental import train,Detector,save_profile,load_profile
from processing.evaluation import CONDITIONS,summarize
from processing.settings import load_settings


def windows_from(path,session_id,participant_id):
    for w in iter_windows(iter_samples(path)):
        record={'window_id':w.id,'session_id':session_id,'participant_id':participant_id,'start':w.start,'end':w.end,
                'continuity_id':hashlib.sha256(repr((w.samples[0].source_id,w.samples[0].epoch,w.samples[0].stable_segment)).encode()).hexdigest(),
                'source_id':w.samples[0].source_id,'epoch':w.samples[0].epoch,'stable_segment':w.samples[0].stable_segment,
                'feature_config_id':CONFIG_ID,'usable':False,'artifact_flags':[],'invalid_reasons':list(w.reasons)}
        if w.valid:
            started=time.perf_counter()
            try:record.update(extract_matrix([s.microvolts for s in w.samples]))
            except ValueError as exc:record['invalid_reasons'].append(str(exc))
            record['processing_seconds']=time.perf_counter()-started
        yield record


def recording_fingerprint(path):
    h=hashlib.sha256();n=0
    for sample in iter_samples(path):
        h.update(json.dumps([sample.counter,sample.adc],separators=(',',':'),allow_nan=False).encode());h.update(b'\n');n+=1
    if not n:raise ValueError('No EEG in recording')
    return h.hexdigest()


def load_dataset(manifest_path):
    source=Path(manifest_path);manifest=json.loads(source.read_text())
    if manifest.get('schema')!='eeg.dataset.v1':raise ValueError('Unsupported dataset schema')
    participant=manifest['participant_id']
    if not isinstance(participant,str) or not participant:raise ValueError('Participant ID required')
    if not isinstance(manifest.get('sessions'),list) or not manifest['sessions']:raise ValueError('Sessions required')
    groups={'train':[],'evaluation':[]};seen_ids=set();seen_content=set();provenance=[]
    for session in manifest['sessions']:
        sid=session['id'];split=session['split']
        if not isinstance(sid,str) or not sid or sid in seen_ids or split not in groups:raise ValueError('Unique session IDs and explicit whole-session split required')
        if session.get('independent_session') is not True:raise ValueError('Explicit independent acquisition declaration required')
        seen_ids.add(sid);path=(source.parent/session['recording']).resolve();fingerprint=recording_fingerprint(path)
        if fingerprint in seen_content:raise ValueError('Duplicate EEG content across sessions')
        seen_content.add(fingerprint);trials=session['trials'];seen_trials=set();intervals=[]
        for trial in trials:
            if trial['id'] in seen_trials:raise ValueError('Duplicate trial ID')
            seen_trials.add(trial['id'])
            if any(type(trial[k]) not in (int,float) for k in ('start','end')):raise ValueError('Numeric trial times required')
            try:a,b=float(trial['start']),float(trial['end'])
            except OverflowError as exc:raise ValueError('Invalid trial interval') from exc
            if not np.isfinite([a,b]).all() or a<0 or b<=a:raise ValueError('Invalid trial interval')
            if any(a<y and b>x for x,y in intervals):raise ValueError('Overlapping labeled trials')
            intervals.append((a,b));trial['start']=a;trial['end']=b
            if not isinstance(trial['label'],str) or not trial['label'] or len(trial['label'])>80:raise ValueError('Invalid class label')
            if trial.get('accepted') is not True or trial.get('label_verified') is not True:raise ValueError('Rejected or uncertain-label trials cannot enter training/evaluation')
            condition=trial.get('condition','cued_neutral' if trial['label']=='neutral' else 'cued_task')
            if condition not in CONDITIONS:raise ValueError('Unsupported trial condition')
            if (condition=='cued_task') != (trial['label']!='neutral'):raise ValueError('Control/ordinary trials must label neutral; cued tasks require a task label')
            if split=='train' and condition not in ('cued_task','cued_neutral'):raise ValueError('Challenge controls are evaluation-only')
            shadow=trial.get('shadow_enabled',True)
            if type(shadow) is not bool or (split=='train' and not shadow):raise ValueError('Invalid shadow state')
            cue=trial.get('cue_completed_at')
            if cue is not None and (type(cue) not in (float,int) or not np.isfinite(cue) or cue<0 or cue>b):raise ValueError('Invalid observed cue time')
            trial.update(condition=condition,shadow_enabled=shadow)
        matched_ids=set()
        accepted=0;rejected=0
        for record in windows_from(path,sid,participant):
            matched=[t for t in trials if t['start']<=record['start'] and record['end']<=t['end']]
            if not matched:continue
            trial=matched[0];matched_ids.add(trial['id'])
            record.update(condition=trial['condition'],shadow_enabled=trial['shadow_enabled'],
                          trial_start=trial['start'],trial_end=trial['end'],cue_completed_at=trial.get('cue_completed_at'))
            record.update(label=trial['label'],trial_id=trial['id'],accepted=True,label_verified=True,recording_content_sha256=fingerprint)
            if split=='train' and not record['usable']:rejected+=1;continue
            groups[split].append(record);accepted+=int(record['usable']);rejected+=int(not record['usable'])
        if split=='evaluation' and matched_ids!=seen_trials:raise ValueError('Evaluation trial has no contained windows; cannot silently omit it')
        provenance.append({'session_id':sid,'split':split,'eeg_content_sha256':fingerprint,'usable_windows':accepted,'rejected_windows':rejected})
    return participant,groups,provenance


def evaluate_profile(profile,records,controls_only=False):
    if not records:raise ValueError('No evaluation windows')
    if {r['session_id'] for r in records}&set(profile['training_sessions']):raise ValueError('Training/evaluation sessions overlap')
    if {r['window_id'] for r in records}&set(profile['training_window_ids']):raise ValueError('Training/evaluation windows overlap')
    if {r.get('recording_content_sha256') for r in records}&set(profile['training_recording_hashes'].values()):raise ValueError('Training/evaluation EEG content overlaps')
    seen_windows=set();session_hashes={}
    for record in records:
        content=record.get('recording_content_sha256');sid=record.get('session_id');wid=record.get('window_id')
        if not isinstance(content,str) or re.fullmatch(r'[0-9a-f]{64}',content) is None:raise ValueError('Evaluation recording content hash required')
        if not isinstance(sid,str) or not sid or not isinstance(wid,str) or not wid or wid in seen_windows:raise ValueError('Unique evaluation windows required')
        if sid in session_hashes and session_hashes[sid]!=content:raise ValueError('One recording hash per session required')
        session_hashes[sid]=content;seen_windows.add(wid)
        if record.get('accepted') is not True or record.get('label_verified') is not True:raise ValueError('Rejected/unverified evaluation labels')
    if len(set(session_hashes.values()))!=len(session_hashes):raise ValueError('Duplicate evaluation recordings')
    classes=profile['classes']
    if controls_only and any(r['label']!='neutral' or r.get('condition') not in CONDITIONS[1:] for r in records):raise ValueError('Controls-only evaluation requires explicit neutral control conditions')
    for label in ([] if controls_only else classes):
        if sum(r['label']==label for r in records)<10:raise ValueError('At least10 evaluation windows per class are required')
    detector=Detector(profile);predictions=[];durations=[]
    for r in records:
        if r.get('label_verified') is not True or r['label'] not in classes:raise ValueError('Unverified or unknown evaluation label')
        tick=time.perf_counter();event=detector.infer(r if r.get('shadow_enabled',True) else dict(r,usable=False));durations.append(time.perf_counter()-tick)
        prediction=event.get('experimental_candidate') or ('neutral' if event.get('reason')=='neutral' else 'reject')
        predictions.append({'actual':r['label'],'predicted':prediction,'trial_id':r['trial_id'],'session_id':r['session_id'],
                            'start':r['start'],'end':r['end'],
                            'condition':r.get('condition','cued_neutral' if r['label']=='neutral' else 'cued_task'),
                            'shadow_enabled':r.get('shadow_enabled',True),'input_usable':r.get('usable') is True,
                            'trial_start':r.get('trial_start',r['start']),'trial_end':r.get('trial_end',r['end']),
                            'cue_completed_at':r.get('cue_completed_at'),'artifact_flags':r.get('artifact_flags',[]),
                            'invalid_reasons':r.get('invalid_reasons',[]),'event':event})
    metrics={}
    for label in classes:
        tp=sum(p['actual']==label and p['predicted']==label for p in predictions);fp=sum(p['actual']!=label and p['predicted']==label for p in predictions);fn=sum(p['actual']==label and p['predicted']!=label for p in predictions)
        metrics[label]={'tp':tp,'fp':fp,'fn':fn,'precision':tp/(tp+fp) if tp+fp else None,'recall':tp/(tp+fn) if tp+fn else None}
    measurements=summarize(predictions)
    ordinary=measurements['conditions'].get('ordinary_activity',{})
    neutral=[p for p in predictions if p['condition']=='cued_neutral'];exposure=sum(p['end']-p['start'] for p in neutral)
    false_windows=sum(p['predicted'] not in ('neutral','reject') for p in neutral)
    # Cued neutral exposure is not ordinary-activity validation; do not relabel it.
    return {'schema':'eeg.mental-evaluation.v1','evaluation_scope':'controls_only' if controls_only else 'full','profile_id':profile['profile_id'],'metrics':metrics,'predictions':predictions,
        'rejection_fraction':sum(p['predicted']=='reject' for p in predictions)/len(predictions),
        'evaluation_sessions':sorted(session_hashes),
        'labeled_trials':len({(r['session_id'],r['trial_id']) for r in records}),
        'uncertainty_interval':None,'uncertainty_note':'No participant-level uncertainty interval: these windows and trials are not independent participants.',
        'calibration_wall_time_seconds':None,
        'cued_neutral_seconds':exposure,'false_positive_neutral_windows':false_windows,
        'shadow_measurements':measurements,
        'ordinary_activity_false_activations_per_hour':ordinary.get('episode_onsets_per_hour'),'ordinary_activity_validated':False,
        'processing_latency_seconds':{'median':float(np.median(durations)),'p95':float(np.quantile(durations,.95))},
        'algorithmic_minimum_persistence_seconds':2*profile['design']['persistence_windows'],'cross_session_evaluation':True,
        'cognitive_score_validated':False,'mental_command_hardware_validated':False,'system_control_enabled':False,
        'limitations':['Window results within trials are correlated; do not use window count as independent physiological trial count.',
        'Processing time excludes headset, BLE, UI and user response latency.',
        'Cued neutral is not ordinary activity. Prospective artifact controls and independently verified labels are still required.']}


def write_json(path,value):
    with new_jsonl(path) as f:json.dump(value,f,indent=2,allow_nan=False);f.write('\n')

@contextmanager
def new_jsonl(path):
    destination=Path(path)
    if destination.exists():raise FileExistsError(str(destination))
    fd,tmp=tempfile.mkstemp(prefix='.eeg-',dir=str(destination.parent))
    try:
        with os.fdopen(fd,'w') as f:
            yield f
            f.flush();os.fsync(f.fileno())
        os.link(tmp,destination)
    finally:
        os.unlink(tmp)


def main():
    p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='command',required=True)
    extract=sub.add_parser('extract');extract.add_argument('recording');extract.add_argument('--session',required=True);extract.add_argument('--participant',required=True);extract.add_argument('--output',required=True)
    fit=sub.add_parser('train');fit.add_argument('dataset');fit.add_argument('--output',required=True);fit.add_argument('--parent-profile');fit.add_argument('--settings')
    evaluate=sub.add_parser('evaluate');evaluate.add_argument('dataset');evaluate.add_argument('--profile',required=True);evaluate.add_argument('--output',required=True);evaluate.add_argument('--controls-only',action='store_true')
    infer=sub.add_parser('replay');infer.add_argument('recording');infer.add_argument('--profile',required=True);infer.add_argument('--session',required=True);infer.add_argument('--participant',required=True);infer.add_argument('--output',required=True)
    a=p.parse_args()
    if a.command in ('extract','replay'):
        detector=Detector(load_profile(a.profile)) if a.command=='replay' else None
        with new_jsonl(a.output) as f:
            for r in windows_from(a.recording,a.session,a.participant):f.write(json.dumps(detector.infer(r) if detector else r,allow_nan=False)+'\n')
    else:
        participant,groups,provenance=load_dataset(a.dataset)
        if a.command=='train':
            parent=load_profile(a.parent_profile) if a.parent_profile else None
            if parent and parent['participant_id']!=participant:raise ValueError('Retraining parent participant mismatch')
            save_profile(train(groups['train'],participant,parent['profile_id'] if parent else None,load_settings(a.settings) if a.settings else None),a.output)
        else:
            report=evaluate_profile(load_profile(a.profile),groups['evaluation'],a.controls_only);report['dataset_provenance']=provenance;write_json(a.output,report)
if __name__=='__main__':main()
