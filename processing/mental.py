"""Independent experimental personalized classifier with explicit rejection.

No fitted artifact is trusted for OS control. Output is a read-only application
proposal with source/profile/feature provenance, never an HID/automation call.
"""
import copy,hashlib,json,math,os,re
from pathlib import Path
import numpy as np
from processing.features import CONFIG_ID,NAMES
from processing.settings import validate_settings,ALGORITHM_KEYS
SCHEMA='eeg.mental-profile.v2'
DESIGN={'origin':'independent_design_not_recovered_cortex','feature_selection':'training-only between/within variance ratio',
        'selected_features':20,'pca_components':8,'gaussian':'diagonal_regularized','variance_floor':0.05,
        'class_prior':'equal','score_threshold':0.9,'margin_threshold':0.25,'persistence_windows':2,
        'parameters_physiologically_validated':False}

def digest(value):return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()

def _validate_parent(parent):
    if parent is not None and (not isinstance(parent,str) or re.fullmatch(r'[0-9a-f]{64}',parent) is None):
        raise ValueError('Parent profile ID must be a lowercase SHA256 or null')

def train(records,participant_id,parent_profile=None,settings=None):
    _validate_parent(parent_profile)
    settings=validate_settings(settings)
    design=dict(DESIGN,**{k:settings[k] for k in ALGORITHM_KEYS})
    if settings['max_training_windows'] is not None and len(records)>settings['max_training_windows']:
        raise ValueError('Configured training resource budget exceeded')
    if not participant_id or not isinstance(participant_id,str):raise ValueError('Explicit participant ID required')
    if not records:raise ValueError('Training windows required')
    if any(r.get('accepted') is not True or r.get('label_verified') is not True for r in records):raise ValueError('Unverified/rejected labels cannot train a profile')
    if any(r.get('feature_config_id')!=CONFIG_ID or r.get('artifact_flags') or r.get('usable') is False for r in records):raise ValueError('Mixed features or flagged windows')
    if any(r.get('participant_id')!=participant_id for r in records):raise ValueError('Participant mismatch')
    ids=[r['window_id'] for r in records]
    if len(set(ids))!=len(ids):raise ValueError('Duplicate windows')
    if any(not isinstance(r.get('session_id'),str) or not r['session_id'] for r in records):
        raise ValueError('Explicit training session IDs required')
    sessions={r['session_id'] for r in records}
    if len(sessions)<2:raise ValueError('At least two independently acquired training sessions required')
    recording_hashes={}
    for record in records:
        session=record['session_id'];content_hash=record.get('recording_content_sha256')
        if not isinstance(content_hash,str) or re.fullmatch(r'[0-9a-f]{64}',content_hash) is None:
            raise ValueError('Canonical recording content SHA256 required')
        if session in recording_hashes and recording_hashes[session]!=content_hash:
            raise ValueError('One recording content hash required per session')
        recording_hashes[session]=content_hash
    if len(set(recording_hashes.values()))!=len(recording_hashes):
        raise ValueError('Duplicate recording content across training sessions')
    labels=sorted({r['label'] for r in records})
    if 'neutral' not in labels or len(labels)<2:raise ValueError('Require neutral and at least one declared task class')
    for label in labels:
        subset=[r for r in records if r['label']==label]
        if len(subset)<20 or len({r['session_id'] for r in subset})<2:raise ValueError('Each class needs20 windows across at least two sessions')
    x=np.asarray([r['values'] for r in records],dtype=float);y=np.asarray([labels.index(r['label']) for r in records])
    if x.shape!=(len(records),len(NAMES)) or not np.isfinite(x).all():raise ValueError('Invalid feature vectors')
    center=x.mean(axis=0);scale=x.std(axis=0);scale[scale<1e-8]=1;z=(x-center)/scale
    means=np.array([z[y==c].mean(axis=0) for c in range(len(labels))]);within=np.mean([np.mean((z[y==c]-means[c])**2,axis=0) for c in range(len(labels))],axis=0)
    ratio=np.var(means,axis=0)/(within+1e-6);selected=np.argsort(-ratio,kind='stable')[:design['selected_features']]
    chosen=z[:,selected];pca_mean=chosen.mean(axis=0);_,_,vt=np.linalg.svd(chosen-pca_mean,full_matrices=False)
    components=vt[:min(design['pca_components'],len(records)-len(labels),len(selected))]
    # Canonicalize SVD signs for deterministic serialization on a given numerical backend.
    for row in components:
        if row[np.argmax(np.abs(row))]<0:row*=-1
    projected=(chosen-pca_mean)@components.T
    gaussian=[]
    for c,label in enumerate(labels):
        data=projected[y==c];mean=data.mean(axis=0);variance=np.maximum(data.var(axis=0),design['variance_floor'])
        distance=np.sum((data-mean)**2/variance,axis=1)
        gaussian.append({'label':label,'mean':mean.tolist(),'variance':variance.tolist(),
                         'distance_limit':max(4*len(mean),float(np.quantile(distance,.99))*1.5)})
    profile={'schema':SCHEMA,'participant_id':participant_id,'parent_profile_id':parent_profile,'feature_config_id':CONFIG_ID,
        'processing_settings':settings,'design':copy.deepcopy(design),'classes':labels,'center':center.tolist(),'scale':scale.tolist(),'selected':selected.tolist(),
        'pca_mean':pca_mean.tolist(),'components':components.tolist(),'gaussians':gaussian,
        'training_sessions':sorted(sessions),'training_recording_hashes':dict(sorted(recording_hashes.items())),'training_window_ids':sorted(ids),'training_records_sha256':digest([{k:v for k,v in r.items() if k!='processing_seconds'} for r in records]),
        'validation_status':'experimental_unvalidated','system_control_enabled':False}
    profile['profile_id']=digest(profile)
    return profile

def validate_profile(profile):
    if not isinstance(profile, dict): raise ValueError('Profile must be an object')
    if profile.get('schema')!=SCHEMA or profile.get('feature_config_id')!=CONFIG_ID:raise ValueError('Unsupported profile or feature configuration')
    check=dict(profile);pid=check.pop('profile_id',None)
    if pid!=digest(check):raise ValueError('Profile integrity mismatch')
    _validate_parent(profile.get('parent_profile_id'))
    if profile.get('parent_profile_id') == pid:raise ValueError('Profile cannot reference itself as parent')
    if profile.get('system_control_enabled') is not False:raise ValueError('Control cannot be enabled by an experimental profile')
    settings=validate_settings(profile.get('processing_settings'))
    if profile.get('processing_settings')!=settings:raise ValueError('Complete processing settings snapshot required')
    design=dict(DESIGN,**{k:settings[k] for k in ALGORITHM_KEYS})
    if profile.get('design') != design or profile.get('validation_status') != 'experimental_unvalidated':
        raise ValueError('Unsupported classifier design or validation status')
    if not isinstance(profile.get('participant_id'), str) or not profile['participant_id']:
        raise ValueError('Profile requires participant identity')
    sessions=profile.get('training_sessions');hashes=profile.get('training_recording_hashes')
    if (not isinstance(sessions,list) or len(sessions)<2 or
        any(not isinstance(s,str) or not s for s in sessions) or len(set(sessions))!=len(sessions) or
        not isinstance(hashes,dict) or set(hashes)!=set(sessions) or
        any(not isinstance(h,str) or re.fullmatch(r'[0-9a-f]{64}',h) is None for h in hashes.values()) or
        len(set(hashes.values()))!=len(hashes)):
        raise ValueError('Invalid training recording provenance')
    classes=profile.get('classes')
    if (not isinstance(classes,list) or len(classes)<2 or
        any(not isinstance(c,str) or not c for c in classes) or
        len(set(classes))!=len(classes) or 'neutral' not in classes):
        raise ValueError('Invalid profile classes')
    def array(name, shape, positive=False):
        try: value=np.asarray(profile[name], dtype=float)
        except (KeyError,TypeError,ValueError) as exc: raise ValueError('Invalid profile '+name) from exc
        if value.shape!=shape or not np.isfinite(value).all() or (positive and not (value>0).all()):
            raise ValueError('Invalid profile '+name)
        return value
    array('center',(len(NAMES),));array('scale',(len(NAMES),),positive=True)
    selected=profile.get('selected')
    if (not isinstance(selected,list) or len(selected)!=design['selected_features'] or
        any(type(i) is not int or not 0<=i<len(NAMES) for i in selected) or len(set(selected))!=len(selected)):
        raise ValueError('Invalid feature selection')
    window_ids=profile.get('training_window_ids')
    if (not isinstance(window_ids,list) or not window_ids or
        any(not isinstance(w,str) or not w for w in window_ids) or
        len(set(window_ids))!=len(window_ids)):
        raise ValueError('Invalid training window identities')
    training_digest=profile.get('training_records_sha256')
    if not isinstance(training_digest,str) or re.fullmatch(r'[0-9a-f]{64}',training_digest) is None:
        raise ValueError('Invalid training records digest')
    dimensions=min(design['pca_components'],len(window_ids)-len(classes),len(selected))
    if dimensions<1:raise ValueError('Insufficient PCA dimensions')
    array('pca_mean',(len(selected),));array('components',(dimensions,len(selected)))
    gaussians=profile.get('gaussians')
    if not isinstance(gaussians,list) or len(gaussians)!=len(classes):raise ValueError('Invalid Gaussian classes')
    for label,g in zip(classes,gaussians):
        if not isinstance(g,dict) or g.get('label')!=label:raise ValueError('Gaussian class order mismatch')
        try:
            mean=np.asarray(g['mean'],dtype=float);variance=np.asarray(g['variance'],dtype=float)
            limit=g['distance_limit']
            if (mean.shape!=(dimensions,) or variance.shape!=(dimensions,) or
                not np.isfinite(mean).all() or not np.isfinite(variance).all() or not (variance>0).all() or
                type(limit) not in (int,float) or not math.isfinite(limit) or limit<=0):
                raise ValueError('Invalid Gaussian parameters')
        except (KeyError,TypeError) as exc:raise ValueError('Invalid Gaussian parameters') from exc
    return profile

def save_profile(profile,path):
    validate_profile(profile)
    with os.fdopen(os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600),'w') as f:json.dump(profile,f,indent=2);f.write('\n');f.flush();os.fsync(f.fileno())

def load_profile(path):return validate_profile(json.loads(Path(path).read_text()))

class Detector:
    def __init__(self,profile):self.profile=copy.deepcopy(validate_profile(profile));self.reset()
    def reset(self):
        self.last_end=None;self.session=None;self.continuity=None;self.pending=None;self.count=0;self.pending_start=None
    def infer(self,record):
        p=self.profile
        base={'schema':'eeg.command-proposal.v1','profile_id':p['profile_id'],'feature_config_id':CONFIG_ID,
              'window_id':record.get('window_id'),'session_id':record.get('session_id'),'end':record.get('end'),
              'source_id':record.get('source_id'),'continuity_id':record.get('continuity_id'),
              'status':'no_reliable_command','command':None,'system_control_enabled':False,'validation_status':p['validation_status']}
        reason=None
        if record.get('feature_config_id')!=CONFIG_ID:reason='feature_configuration_mismatch'
        elif record.get('artifact_flags') or record.get('usable') is not True:reason='invalid_or_artifact_window'
        elif record.get('participant_id')!=p['participant_id']:reason='participant_mismatch'
        elif any(not isinstance(record.get(key),str) or not record[key] for key in ('session_id','window_id')):reason='missing_recording_identity'
        elif not isinstance(record.get('continuity_id'),str) or not record['continuity_id']:reason='missing_continuity_identity'
        if reason:self.reset();return dict(base,reason=reason)
        try: x=np.asarray(record.get('values'),dtype=float)
        except (TypeError,ValueError):
            self.reset()
            return dict(base,reason='invalid_features')
        if x.shape!=(len(NAMES),) or not np.isfinite(x).all():self.reset();return dict(base,reason='invalid_features')
        end=record.get('end');start=record.get('start')
        if type(end) not in (int,float) or type(start) not in (int,float) or not math.isfinite(end) or not math.isfinite(start) or start<0 or end<=start:
            self.reset()
            return dict(base,reason='invalid_timing')
        if self.session==record['session_id'] and self.continuity==record['continuity_id'] and self.last_end is not None and start<self.last_end:
            self.reset()
            return dict(base,reason='overlapping_or_reordered_window')
        if self.session!=record.get('session_id') or self.continuity!=record['continuity_id'] or self.last_end is None or abs(start-self.last_end)>.05:self.pending=None;self.count=0
        self.session=record.get('session_id');self.continuity=record['continuity_id'];self.last_end=end
        # Finite inputs can still overflow normalization or squared distances.
        # Reject numerical failure explicitly instead of exposing NaN class scores.
        try:
            with np.errstate(over='raise',invalid='raise',divide='raise',under='ignore'):
                z=((x-p['center'])/p['scale'])[p['selected']];q=(z-p['pca_mean'])@np.asarray(p['components']).T
                scores=[];distances=[]
                for g in p['gaussians']:
                    variance=np.asarray(g['variance']);d=float(np.sum((q-g['mean'])**2/variance));distances.append(d);scores.append(-.5*(d+np.log(2*np.pi*variance).sum()))
                scores=np.asarray(scores);prob=np.exp(scores-scores.max());prob/=prob.sum()
                if not np.isfinite(prob).all():raise FloatingPointError('Nonfinite class scores')
        except FloatingPointError:
            self.reset()
            return dict(base,reason='numerical_failure')
        order=np.argsort(-prob);best=int(order[0]);label=p['classes'][best]
        base['uncalibrated_class_scores']=dict(zip(p['classes'],prob.tolist()));base['candidate_label']=label
        if distances[best]>p['gaussians'][best]['distance_limit']:reason='out_of_training_distribution'
        elif prob[best]<p['design']['score_threshold'] or prob[best]-prob[order[1]]<p['design']['margin_threshold']:reason='ambiguous_score'
        elif label=='neutral':reason='neutral'
        if reason:self.reset();return dict(base,reason=reason)
        self.count=self.count+1 if self.pending==label else 1;self.pending=label
        if self.count==1:self.pending_start=start
        if self.count<p['design']['persistence_windows']:return dict(base,reason='insufficient_persistence')
        # Expose a proposal for evaluation, never a validated command/action.
        return dict(base,reason='profile_not_hardware_validated',experimental_candidate=label,candidate_evidence_start=self.pending_start)
