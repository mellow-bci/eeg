import csv
import io
import json
import tempfile
import unittest
from pathlib import Path

from fixture_support import fixture_path
from recordings import RecordingLibrary, RecordingError


def sample(index):
    return {'kind': 'eeg_adc', 'stream_index': index, 'received_at': index / 128,
            'counter': index % 128, 'epoch': 1, 'transport_stable': index >= 2,
            'continuous': True, 'electrodes_adc': {'AF3': index, 'F7': index + 2},
            'electrodes_microvolts': {'AF3': index / 7.8, 'F7': (index + 2) / 7.8}}


class RecordingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.library = RecordingLibrary(self.root)

    def write(self, events, name='capture.jsonl'):
        (self.root / name).write_text(''.join(json.dumps(e) + '\n' for e in events))

    def test_completion_is_not_capture_cleanliness(self):
        self.write([{'kind': 'stream_start'}, sample(0), {'kind': 'summary', 'capture_clean': False}])
        result = self.library.describe('capture.jsonl')
        self.assertEqual(result['status'], 'complete')
        self.assertFalse(result['capture_clean'])
        self.assertEqual(result['samples'], 1)
        self.write([{'kind': 'stream_start'}, sample(0)])
        self.assertEqual(self.library.describe('capture.jsonl')['status'], 'incomplete')

    def test_truncated_and_malformed(self):
        for content in ('{"kind":', 'not-json\n', '[]\n', '{"kind":"summary","value":NaN}\n'):
            (self.root / 'bad.jsonl').write_text(content)
            self.assertEqual(self.library.describe('bad.jsonl')['status'], 'incomplete' if content == '{"kind":' else 'corrupt')
            with self.assertRaises(RecordingError):
                self.library.replay('bad.jsonl')

    def test_traversal_and_symlink_rejected(self):
        self.write([sample(0)])
        for name in ('../capture.jsonl', '/tmp/capture.jsonl', 'sub/capture.jsonl', 'a\\b.jsonl', 'capture.csv'):
            with self.assertRaises(RecordingError):
                self.library.describe(name)
        (self.root / 'alias.jsonl').symlink_to(self.root / 'capture.jsonl')
        with self.assertRaises(RecordingError):
            self.library.describe('alias.jsonl')
        self.assertEqual([r['name'] for r in self.library.inventory()], ['capture.jsonl'])

    def test_pagination_and_stability_filter(self):
        self.write([sample(i) for i in range(10)])
        page = self.library.replay('capture.jsonl', limit=2, stride=3, channels=['AF3'])
        self.assertEqual([s['stream_index'] for s in page['samples']], [0, 3])
        self.assertEqual(page['next_offset'], 6)
        following = self.library.replay('capture.jsonl', offset=6, limit=2, stride=3, channels=['AF3'])
        self.assertEqual([s['stream_index'] for s in following['samples']], [6, 9])
        self.assertIsNone(following['next_offset'])
        stable = self.library.replay('capture.jsonl', channels=['AF3'], stable_only=True)
        self.assertEqual(stable['samples'][0]['stream_index'], 2)
        with self.assertRaises(RecordingError):
            self.library.replay('capture.jsonl', limit=True)
        with self.assertRaises(RecordingError):
            self.library.replay('capture.jsonl', channels=['AF3', 'AF3'])

    def test_no_voltage_fallback_and_csv_injection(self):
        item = sample(0)
        del item['electrodes_microvolts']
        self.write([item])
        with self.assertRaises(RecordingError):
            self.library.export_csv('capture.jsonl', io.StringIO(), channels=['AF3'], units='microvolts')
        item['counter'] = '=HYPERLINK("https://example.com")'
        self.write([item])
        with self.assertRaises(RecordingError):
            self.library.export_csv('capture.jsonl', io.StringIO(), channels=['AF3'])

    def test_export_real_capture_matches_values_and_summary(self):
        fixture = fixture_path('epoc-cortex-retest-20260915-01.jsonl')
        real = RecordingLibrary(fixture.parent)
        output = io.StringIO()
        result = real.export_csv(fixture.name, output, channels=['AF3', 'O2'], units='microvolts', stable_only=True)
        self.assertEqual(result['samples'], 15108)
        rows = list(csv.DictReader(io.StringIO(output.getvalue())))
        self.assertEqual(len(rows), 15108)
        replay = real.replay(fixture.name, limit=1, channels=['AF3', 'O2'], units='microvolts', stable_only=True)
        self.assertEqual(float(rows[0]['AF3']), replay['samples'][0]['values']['AF3'])
        self.assertEqual(real.describe(fixture.name)['samples'], 15374)


if __name__ == '__main__':
    unittest.main()
