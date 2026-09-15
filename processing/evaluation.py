"""Independent shadow-evaluation measurements; no psychological interpretation.

Episodes are rising edges of persistent proposals, not each proposal window.
Arrival timestamps are preserved; neither physiological onset nor live latency is inferred.
"""
import math
from scipy.stats import chi2

CONDITIONS = ('cued_task', 'cued_neutral', 'ordinary_activity',
              'blink_control', 'jaw_control', 'head_movement_control')


def summarize(predictions):
    trials = {}
    previous = None
    last_end = {}
    episodes = []
    for row in predictions:
        sid, tid = row['session_id'], row['trial_id']
        start, end = row['start'], row['end']
        if not all(type(v) in (int, float) and math.isfinite(v) for v in (start, end)) or start < 0 or end <= start:
            raise ValueError('Invalid evaluation time interval')
        if start < last_end.get(sid, -math.inf):
            raise ValueError('Overlapping or unordered evaluation windows')
        last_end[sid] = end
        condition = row['condition']
        if (condition=='cued_task') != (row['actual']!='neutral'):
            raise ValueError('Condition and target label disagree')
        if type(row['shadow_enabled']) is not bool or type(row['input_usable']) is not bool:
            raise ValueError('Explicit Boolean shadow/input state required')
        if condition not in CONDITIONS:
            raise ValueError('Explicit supported evaluation condition required')
        key = (sid, tid)
        identity = (row['trial_start'], row['trial_end'], condition, row['actual'], row.get('cue_completed_at'))
        if key not in trials:
            a, b = identity[:2]
            if not all(type(v) in (int, float) and math.isfinite(v) for v in (a, b)) or a < 0 or b <= a:
                raise ValueError('Invalid trial interval')
            if any(other['session_id'] == sid and a < other['end'] and b > other['start'] for other in trials.values()):
                raise ValueError('Overlapping trial intervals')
            cue = identity[-1]
            if cue is not None and (type(cue) not in (int, float) or not math.isfinite(cue) or cue < 0 or cue > b):
                raise ValueError('Invalid observed cue completion time')
            trials[key] = {'identity': identity, 'session_id': sid, 'trial_id': tid,
                           'condition': condition, 'actual': row['actual'], 'start': a, 'end': b,
                           'eligible_seconds': 0., 'unarmed_seconds': 0., 'signal_rejected_seconds': 0.,
                           'covered_seconds': 0., 'candidate_windows': 0, 'candidate_window_seconds': 0., 'carry_in_candidates': 0,
                           'episodes': [], 'cue_completed_at': cue}
        trial = trials[key]
        if trial['identity'] != identity or start < trial['start'] or end > trial['end']:
            raise ValueError('Inconsistent trial metadata or containment')
        duration = end - start
        trial['covered_seconds'] += duration
        armed = row['shadow_enabled'] is True
        usable = row['input_usable'] is True
        if not armed:
            trial['unarmed_seconds'] += duration
        elif not usable:
            trial['signal_rejected_seconds'] += duration
        else:
            trial['eligible_seconds'] += duration
        label = row['event'].get('experimental_candidate') if armed and usable else None
        continuity = row['event'].get('continuity_id')
        evidence_start=row['event'].get('candidate_evidence_start')
        if label and (type(evidence_start) not in (int,float) or not math.isfinite(evidence_start) or evidence_start<0 or evidence_start>start):
            raise ValueError('Invalid candidate evidence chronology')
        if label and not continuity:
            raise ValueError('Candidate lacks continuity provenance')
        same = (previous is not None and previous['label'] == label and label is not None
                and previous['session'] == sid and previous['continuity'] == continuity
                and 0 <= start - previous['end'] <= .05)
        if label:
            trial['candidate_windows'] += 1
            trial['candidate_window_seconds'] += duration
            if not same and evidence_start<trial['start']:
                trial['carry_in_candidates'] += 1
            elif not same:
                event = {'session_id': sid, 'trial_id': tid, 'label': label,
                         'input_available_at': end, 'condition': condition,
                         'evidence_start': row['event'].get('candidate_evidence_start')}
                episodes.append(event)
                trial['episodes'].append(event)
            elif previous['trial'] != tid:
                trial['carry_in_candidates'] += 1
        previous = {'label': label, 'session': sid, 'trial': tid, 'continuity': continuity, 'end': end}

    by_condition = {}
    trial_results = []
    for trial in trials.values():
        trial.pop('identity')
        trial['unobserved_seconds'] = max(0., trial['end'] - trial['start'] - trial['covered_seconds'])
        cue = trial['cue_completed_at']
        matched = [e for e in trial['episodes'] if e['label'] == trial['actual'] and cue is not None and e['evidence_start'] is not None and e['evidence_start'] >= cue]
        trial['first_cue_associated_candidate_latency_seconds'] = (
            matched[0]['input_available_at'] - cue if matched and trial['condition'] == 'cued_task' else None)
        trial['cued_target_detected'] = bool(matched) if cue is not None and trial['condition'] == 'cued_task' else None
        trial_results.append(trial)
    for condition in CONDITIONS:
        rows = [t for t in trial_results if t['condition'] == condition]
        if not rows:
            continue
        eligible = sum(t['eligible_seconds'] for t in rows)
        count = sum(len(t['episodes']) for t in rows)
        carries = sum(t['carry_in_candidates'] for t in rows)
        # A carried activation invalidates a clean onset-rate interpretation; expose it.
        can_rate = eligible > 0 and carries == 0
        by_condition[condition] = {
            'trials': len(rows), 'eligible_seconds': eligible,
            'unarmed_seconds': sum(t['unarmed_seconds'] for t in rows),
            'signal_rejected_seconds': sum(t['signal_rejected_seconds'] for t in rows),
            'unobserved_seconds': sum(t['unobserved_seconds'] for t in rows),
            'candidate_windows': sum(t['candidate_windows'] for t in rows),
            'candidate_window_seconds': sum(t['candidate_window_seconds'] for t in rows),
            'episode_onsets': count, 'carry_in_candidates': carries,
            'episode_onsets_per_hour': count * 3600 / eligible if can_rate else None,
            'one_sided_95_percent_poisson_upper_per_hour': float(chi2.ppf(.95, 2*(count+1))*.5*3600/eligible) if can_rate else None,
        }
    return {'schema': 'eeg.shadow-measurements.v1', 'episodes': episodes,
            'trials': trial_results, 'conditions': by_condition,
            'hardware_validated': False,
            'limitations': [
                'Episodes are proposal rising edges; repeated candidate windows remain separately counted.',
                'No refractory period is added by evaluation; neutral, rejection, gaps and continuity changes end an episode.',
                'Latency is relative to observed cue completion and last input arrival, not verified mental onset or live system latency.',
                'Poisson upper bounds assume a constant independent event rate; clustered events weaken this assumption.',
                'Carry-in activity makes onset rates unavailable rather than being credited as clean neutral exposure.',
                'Explicit condition labels are declarations, not proof of physiological source or task compliance.',
            ]}
