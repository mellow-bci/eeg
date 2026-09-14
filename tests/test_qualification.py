import json
from pathlib import Path
import tempfile
import unittest
from tools.qualify_recording import qualify


class QualificationTests(unittest.TestCase):
    def recording(self):
        rows = [{'kind': 'stream_start', 'epoch': 1}]
        for index in range(514):
            if index == 256:
                rows.append({'kind': 'transport_status', 'status': 'stable', 'epoch': 1})
            rows.append({'kind': 'eeg_adc', 'epoch': 1, 'received_at': (index//2)/64,
                         'counter': index % 128, 'transport_stable': index >= 256,
                         'consumer_eligible': index >= 256, 'stable_segment': 1 if index >= 256 else None})
        rows.append({'kind': 'summary', 'samples': 514, 'stable_samples': 258,
                     'decode_errors': 0, 'fatal_error': None, 'connection_errors': 0,
                     'transport_interruptions': 0})
        return rows

    def report(self, rows, **kwargs):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'capture.jsonl'
            path.write_text(''.join(json.dumps(r)+'\n' if isinstance(r, dict) else r+'\n' for r in rows))
            return qualify(path, min_seconds=3, min_stable_seconds=1, **kwargs)

    def test_complete_contiguous_capture(self):
        report = self.report(self.recording())
        self.assertEqual(report['status'], 'PASS')
        self.assertEqual(report['epochs'][0]['observed_arrival_rate_hz'], 128)
        self.assertFalse(report['production_certified'])

    def test_truncation_fails(self):
        report = self.report(self.recording()[:-1])
        self.assertEqual(report['status'], 'FAIL')
        self.assertFalse(report['checks']['single_terminal_summary'])

    def test_startup_requires_explicit_policy(self):
        rows = self.recording()
        rows.insert(1, {'kind': 'decode_error'})
        rows[-1]['decode_errors'] = 1
        self.assertEqual(self.report(rows)['status'], 'FAIL')
        self.assertEqual(self.report(rows, allow_startup_errors=True)['status'], 'PASS')

    def test_recovery_errors_stay_post_readiness(self):
        rows = self.recording()
        rows.insert(-1, {'kind': 'transport_status', 'status': 'recovering'})
        rows.insert(-1, {'kind': 'decode_error'})
        rows[-1]['decode_errors'] = 1
        report = self.report(rows, allow_startup_errors=True)
        self.assertEqual(report['status'], 'FAIL')
        self.assertEqual(report['post_readiness_issues']['decode_error'], 1)

    def test_deleted_sample_detected_despite_summary(self):
        rows = self.recording()
        del rows[-4]
        report = self.report(rows)
        self.assertFalse(report['checks']['summary_sample_counts_match'])
        self.assertIn('counter_gap', report['post_readiness_issues'])

    def test_malformed_and_trailing_events_fail(self):
        rows = self.recording()+['broken', {'kind': 'extra'}]
        report = self.report(rows)
        self.assertFalse(report['checks']['valid_jsonl'])
        self.assertFalse(report['checks']['single_terminal_summary'])

    def test_invalid_sample_clock_fails(self):
        rows = self.recording()
        rows[-3]['received_at'] = -1
        self.assertEqual(self.report(rows)['status'], 'FAIL')

    def test_invalid_threshold_rejected(self):
        with self.assertRaises(ValueError):
            qualify('/nonexistent', expected_hz=float('nan'))
