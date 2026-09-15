"""Synthetic episode/exposure arithmetic, not physiological evidence."""
import copy
import unittest
from processing.evaluation import summarize


def row(start, candidate=None, trial='ordinary', condition='ordinary_activity', usable=True, armed=True):
    event={'continuity_id':'segment-1'}
    if candidate:event.update(experimental_candidate=candidate,candidate_evidence_start=max(0,start-2))
    return {'session_id':'test','trial_id':trial,'start':start,'end':start+2,
            'trial_start':0,'trial_end':10,'actual':'neutral','condition':condition,
            'shadow_enabled':armed,'input_usable':usable,'event':event,'cue_completed_at':None}


class ShadowTests(unittest.TestCase):
    def test_persistent_windows_are_one_episode(self):
        result=summarize([row(0,'task'),row(2,'task'),row(4,'task'),row(6),row(8,'task')])
        stats=result['conditions']['ordinary_activity']
        self.assertEqual(stats['candidate_windows'],4)
        self.assertEqual(stats['episode_onsets'],2)
        self.assertEqual(stats['eligible_seconds'],10)
        self.assertEqual(stats['episode_onsets_per_hour'],720)

    def test_unavailable_unarmed_and_abstention_exposure(self):
        result=summarize([row(0),row(2,usable=False),row(4,armed=False),row(8)])
        stats=result['conditions']['ordinary_activity']
        self.assertEqual(stats['eligible_seconds'],4) # Valid abstention is eligible.
        self.assertEqual(stats['unarmed_seconds'],2)
        self.assertEqual(stats['signal_rejected_seconds'],2)
        self.assertEqual(stats['unobserved_seconds'],2)
        self.assertAlmostEqual(stats['one_sided_95_percent_poisson_upper_per_hour'],2.99573227355*900,places=6)
        unavailable=summarize([row(0,usable=False)])['conditions']['ordinary_activity']
        self.assertIsNone(unavailable['episode_onsets_per_hour'])

    def test_cued_neutral_not_ordinary(self):
        stats=summarize([row(0,condition='cued_neutral')])['conditions']
        self.assertNotIn('ordinary_activity',stats)

    def test_condition_transition_does_not_create_event(self):
        a=row(0,'task',trial='task',condition='cued_task');a.update(trial_end=2,actual='task')
        b=row(2,'task');b['trial_start']=2
        stats=summarize([a,b])['conditions']['ordinary_activity']
        self.assertEqual(stats['episode_onsets'],0)
        self.assertEqual(stats['carry_in_candidates'],1)
        self.assertIsNone(stats['episode_onsets_per_hour'])

    def test_pending_cross_condition_and_future_evidence(self):
        a=row(0,trial='task',condition='cued_task');a.update(trial_end=2,actual='task')
        b=row(2,'task');b['trial_start']=2
        stats=summarize([a,b])['conditions']['ordinary_activity']
        self.assertEqual(stats['carry_in_candidates'],1)
        self.assertIsNone(stats['episode_onsets_per_hour'])
        b['event']['candidate_evidence_start']=100
        with self.assertRaises(ValueError):summarize([a,b])

    def test_gap_and_continuity_reset(self):
        a=row(0,'task');b=row(4,'task');c=row(6,'task');c['event']['continuity_id']='segment-2'
        self.assertEqual(len(summarize([a,b,c])['episodes']),3)

    def test_observed_cue_and_postcue_evidence_required(self):
        a=row(0,'task',condition='cued_task');a.update(actual='task',cue_completed_at=1)
        b=row(2,'task',condition='cued_task');b.update(actual='task',cue_completed_at=1)
        result=summarize([a,b])['trials'][0]
        self.assertFalse(result['cued_target_detected'])
        self.assertIsNone(result['first_cue_associated_candidate_latency_seconds'])
        a=row(4,'task',condition='cued_task');a.update(actual='task',cue_completed_at=1)
        result=summarize([a])['trials'][0]
        self.assertEqual(result['first_cue_associated_candidate_latency_seconds'],5)
        a['cue_completed_at']=None
        self.assertIsNone(summarize([a])['trials'][0]['cued_target_detected'])

    def test_negative_receipt_clock_metadata_is_rejected(self):
        for field in ('start', 'trial_start', 'cue_completed_at'):
            value=row(0)
            value[field]=-1
            with self.subTest(field=field), self.assertRaises(ValueError):summarize([value])
        value=row(0, 'task');value['event']['candidate_evidence_start']=-1
        with self.assertRaises(ValueError):summarize([value])

    def test_overlaps_and_inconsistent_trials_rejected(self):
        variants=[[row(0),row(1)],[row(0),row(2,condition='blink_control')],
                  [row(0),row(2,trial='different')]]
        for rows in variants:
            with self.assertRaises(ValueError):summarize(rows)

if __name__=='__main__':unittest.main()
