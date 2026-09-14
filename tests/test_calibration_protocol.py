import contextlib
import io
import json
import os
import stat
import tempfile
import unittest
from collections import Counter
from pathlib import Path
from calibration.protocol import generate_protocol, write_manifest, main


class CalibrationProtocolTests(unittest.TestCase):
    def test_balanced_reproducible_and_varies_with_seed(self):
        for protocol, labels in [('eyes_open_closed', {'eyes_open', 'eyes_closed'}),
                                 ('blink_neutral', {'deliberate_blink', 'neutral'})]:
            manifest = generate_protocol(protocol, 42)
            self.assertEqual(manifest, generate_protocol(protocol, 42))
            trials = [event for event in manifest['events'] if event['trial_id']]
            self.assertEqual(Counter(e['label'] for e in trials), {label: 6 for label in labels})
            other = generate_protocol(protocol, 43)
            self.assertNotEqual([e['label'] for e in manifest['events']],
                                [e['label'] for e in other['events']])

    def test_schedule_offsets_final_reopening_and_no_results(self):
        manifest = generate_protocol('eyes_open_closed', 0, trial_count=4,
                                     block_seconds=7, initial_rest_seconds=5)
        events = manifest['events']
        self.assertEqual([e['offset_seconds'] for e in events], [0, 5, 12, 19, 26, 33])
        self.assertEqual([e['duration_seconds'] for e in events], [5, 7, 7, 7, 7, 0])
        self.assertEqual(len({e['event_id'] for e in events}), len(events))
        self.assertIn('Open your eyes', events[-1]['cue_text'])
        self.assertFalse(manifest['validation_result'])
        self.assertFalse(manifest['execution']['executed'])
        self.assertEqual(manifest['experiment_type'], 'training_experiment')
        for prohibited in ('metrics', 'accuracy', 'train', 'test', 'split'):
            self.assertNotIn(prohibited, manifest)
        self.assertTrue(all(isinstance(e['cue_text'], str) and e['cue_text'] for e in events))

    def test_invalid_parameters(self):
        for changes in ({'protocol': 'flashing'}, {'seed': True}, {'seed': -1},
                        {'seed': 2**64}, {'trial_count': 3}, {'trial_count': 0},
                        {'block_seconds': 0}, {'block_seconds': float('nan')},
                        {'initial_rest_seconds': -2}, {'trial_count': True}):
            args = {'protocol': 'eyes_open_closed', 'seed': 1}
            args.update(changes)
            with self.assertRaises(ValueError):
                generate_protocol(**args)

    def test_private_exclusive_file_and_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / 'protocol.json'
            manifest = generate_protocol('blink_neutral', 123)
            write_manifest(manifest, destination)
            self.assertEqual(json.loads(destination.read_text()), manifest)
            self.assertEqual(stat.S_IMODE(destination.stat().st_mode), 0o600)
            before = destination.read_bytes()
            with self.assertRaises(FileExistsError):
                write_manifest(manifest, destination)
            self.assertEqual(destination.read_bytes(), before)
            alias = Path(directory) / 'alias.json'
            alias.symlink_to(destination)
            with self.assertRaises(FileExistsError):
                write_manifest(manifest, alias)
            self.assertEqual(destination.read_bytes(), before)

    def test_cli_generation_and_repeated_output_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / 'plan.json'
            args = ['generate', '--protocol', 'eyes_open_closed', '--seed', '92', '--output', str(destination)]
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(main(args), 0)
            self.assertEqual(json.loads(destination.read_text())['seed'], 92)
            with contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as failure:
                    main(args)
            self.assertEqual(failure.exception.code, 2)


if __name__ == '__main__':
    unittest.main()
