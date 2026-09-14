import unittest
import numpy as np
from calibration.evaluate import fit_lda,predict,wilson,evaluate,features
class CalibrationTests(unittest.TestCase):
    def test_training_parameters_are_frozen(self):
        m=fit_lda([[0,0],[.1,0],[2,2],[2.1,2]],[0,0,1,1]);before=repr(m)
        self.assertEqual(predict(m,[[.05,0],[2.05,2]]).tolist(),[0,1]);predict(m,[[10000,10000]]);self.assertEqual(repr(m),before)
    def test_uncertainty_not_zero_for_zero_errors(self):
        lo,hi=wilson(0,10);self.assertEqual(lo,0);self.assertGreater(hi,.2)
    def test_no_sessions_rejected(self):
        with self.assertRaises(ValueError):evaluate({'protocol':'eyes','sessions':[]})
    def test_unstable_trial_rejected(self):
        with self.assertRaises(ValueError):features([{'received_at':0}],0,4,'eyes')
    def test_eye_features_on_synthetic_signal_not_physiological_evidence(self):
        rows=[]
        for i in range(640):
            x=4000+20*np.sin(2*np.pi*10*i/128)
            rows.append({'received_at':i/128,'transport_stable':True,'continuous':True,'epoch':1,'stable_segment':1,'stream_index':i,'electrodes_microvolts':{'O1':x,'O2':x}})
        f=features(rows,0,5,'eyes');self.assertGreater(f[0],.99)
        rows[50]['stream_index']=70
        with self.assertRaises(ValueError):features(rows,0,5,'eyes')

# These tests isolate manifest/scoring contracts using synthetic files and stubbed
# features. Their accuracy values are software checks, not physiological evidence.
import copy
import json
import tempfile
from pathlib import Path
from unittest.mock import patch

class ManifestGatingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.base = Path(self.directory.name)
        self.sessions = []
        for index, split in enumerate(('train', 'train', 'test')):
            recording = 'session-%d.jsonl' % index
            row = {'kind': 'eeg_adc', 'stream_index': 0, 'received_at': 0,
                   'electrodes_microvolts': {'O1': 4000 + index, 'O2': 4001 + index}}
            (self.base / recording).write_text(json.dumps(row) + '\n')
            self.sessions.append({'session_id': 'session-%d' % index,
                                  'participant_id': 'synthetic-person', 'split': split,
                                  'recording': recording, 'labels_verified': True,
                                  'trials': [{'trial_id': 'trial-%d' % t,
                                              'label': 'eyes_open' if t % 2 == 0 else 'eyes_closed',
                                              'start': t * 5, 'end': t * 5 + 4}
                                             for t in range(20)]})
        self.manifest = {'protocol': 'eyes', 'sessions': self.sessions}
        self.feature_stub = patch('calibration.evaluate.features',
                                  side_effect=lambda rows, start, end, protocol: [float(int(start / 5) % 2), .2])
        self.feature_stub.start()
        self.addCleanup(self.feature_stub.stop)

    def assert_rejected(self, phrase):
        with patch('calibration.evaluate.fit_lda') as fit:
            with self.assertRaisesRegex(ValueError, phrase):
                evaluate(self.manifest, self.base)
            fit.assert_not_called()

    def test_identical_recording_bytes_cannot_cross_splits(self):
        original = self.base / self.sessions[0]['recording']
        destination = self.base / self.sessions[2]['recording']
        destination.write_bytes(original.read_bytes())
        self.assert_rejected('Recording reused.*data leakage')

    def test_reserialized_same_eeg_with_changed_metadata_rejected(self):
        original = json.loads((self.base / self.sessions[0]['recording']).read_text())
        original['received_at'] = 999
        original['stream_index'] = 555
        rewritten = json.dumps(original, separators=(',', ':'))
        (self.base / self.sessions[2]['recording']).write_text('{"kind":"stream_start","device":"another-name"}\n' + rewritten + '\n')
        self.assert_rejected('EEG content reused.*data leakage')

    def test_overlapping_trials_rejected_before_fit(self):
        self.sessions[0]['trials'][1]['start'] = 3
        self.assert_rejected('Overlapping trials')

    def test_touching_nonoverlapping_trials_accepted(self):
        for session in self.sessions:
            for t, trial in enumerate(session['trials']):
                trial['start'], trial['end'] = t * 4, (t + 1) * 4
        report = evaluate(self.manifest, self.base)
        self.assertEqual(report['test_trials'], 20)
        self.assertEqual(len(report['provenance']), 3)
        self.assertTrue(all(len(p['eeg_content_sha256']) == 64 for p in report['provenance']))
        self.assertFalse(report['system_control_enabled'])

    def test_insufficient_training_sessions_rejected(self):
        self.manifest['sessions'] = [self.sessions[0], self.sessions[2]]
        self.assert_rejected('two training sessions')

    def test_missing_test_session_rejected(self):
        self.manifest['sessions'] = self.sessions[:2]
        self.assert_rejected('independent test session')

    def test_insufficient_class_count_in_either_split_rejected(self):
        baseline = copy.deepcopy(self.sessions)
        for split in ('train', 'test'):
            with self.subTest(split=split):
                self.manifest['sessions'] = copy.deepcopy(baseline)
                for session in self.manifest['sessions']:
                    if session['split'] == split:
                        session['trials'] = session['trials'][:4]
                self.assert_rejected('ten trials per class')

    def test_duplicate_session_id_and_unrecognized_split_rejected(self):
        self.sessions[2]['session_id'] = self.sessions[0]['session_id']
        self.assert_rejected('Unique session IDs')
        self.sessions[2]['session_id'] = 'new-id'
        self.sessions[2]['split'] = 'window-test'
        self.assert_rejected('never individual windows')

    def test_labels_verified_must_be_literal_true(self):
        for value in (False, 'false', 1, None):
            with self.subTest(value=value):
                self.sessions[0]['labels_verified'] = value
                self.assert_rejected('compliance must be explicitly verified')

    def test_participant_mixing_rejected(self):
        self.sessions[2]['participant_id'] = 'another-person'
        self.assert_rejected('one explicit participant ID')

if __name__ == '__main__':
    unittest.main()
