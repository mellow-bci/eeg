"""Deterministic consumer isolation tests; no hardware required."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

from stream import ConsumerDelivery, Pipeline, AcquisitionFailure


class ConsumerDeliveryTests(unittest.TestCase):
    def test_fifo_deep_copy_and_drain(self):
        delivered = []
        worker = ConsumerDelivery(delivered.append, 16, 1)
        sample = {'adc': [1], 'stream_index': 0}
        worker.submit(sample)
        sample['adc'][0] = 99
        worker.submit({'adc': [2], 'stream_index': 1})
        result = worker.close(1)
        self.assertEqual(delivered, [{'adc': [1], 'stream_index': 0}, {'adc': [2], 'stream_index': 1}])
        self.assertEqual(result['delivered'], 2)
        self.assertFalse(result['worker_alive'])
        self.assertIsNone(result['error'])

    def test_hanging_sink_does_not_block_submit_or_shutdown(self):
        entered, release = threading.Event(), threading.Event()
        def sink(sample):
            entered.set()
            release.wait(2)
        worker = ConsumerDelivery(sink, 4, 0.04)
        try:
            worker.submit({'stream_index': 0})
            self.assertTrue(entered.wait(1))
            started = time.monotonic()
            result = worker.close(0.08)
            self.assertLess(time.monotonic()-started, 0.3)
            self.assertEqual(result['error'], 'sample_consumer_timeout')
            self.assertEqual(result['undelivered'], 1)
        finally:
            release.set()
            worker.thread.join(1)

    def test_expired_callback_is_checked_when_shutdown_loop_is_skipped(self):
        entered, release = threading.Event(), threading.Event()
        def sink(sample):
            entered.set(); release.wait(2)
        worker = ConsumerDelivery(sink, 4, 0.04)
        try:
            worker.submit({})
            self.assertTrue(entered.wait(1))
            with worker.lock:
                active = worker.active_since
            # Simulate the closing thread resuming after its deadline without
            # depending on the runner's scheduler or wall-clock sleep precision.
            with patch('stream.time.monotonic', return_value=active + 1):
                result = worker.close(0)
            self.assertEqual(result['error'], 'sample_consumer_timeout')
            self.assertEqual(result['undelivered'], 1)
        finally:
            release.set(); worker.thread.join(1)

    def test_overflow_is_explicit_and_aborts_backlog(self):
        entered, release = threading.Event(), threading.Event()
        received = []
        def sink(sample):
            entered.set()
            release.wait(2)
            received.append(sample)
        worker = ConsumerDelivery(sink, 1, 1)
        try:
            worker.submit({'stream_index': 0})
            self.assertTrue(entered.wait(1))
            worker.submit({'stream_index': 1})
            worker.submit({'stream_index': 2})
            self.assertEqual(worker.check(), 'sample_consumer_overflow')
        finally:
            release.set()
            worker.thread.join(1)
        result = worker.close(1)
        self.assertEqual([s['stream_index'] for s in received], [0])
        self.assertEqual(result['submitted'], 2)
        self.assertEqual(result['undelivered'], 1)

    def test_exception_propagates_via_pipeline_even_without_new_packets(self):
        raised = threading.Event()
        def sink(sample):
            raised.set()
            raise RuntimeError('test')
        with tempfile.TemporaryDirectory() as directory:
            pipeline = Pipeline(Path(directory)/'data.jsonl', sample_sink=sink)
            pipeline.consumer.submit({'stream_index': 0})
            self.assertTrue(raised.wait(1))
            pipeline.consumer.thread.join(1)
            with self.assertRaises(AcquisitionFailure):
                pipeline.check_freshness(1)
            result = pipeline.finish()
            self.assertEqual(result['fatal_error'], 'sample_consumer_failed')
            self.assertFalse(result['capture_clean'])
            self.assertTrue(pipeline.file.closed)

    def test_short_shutdown_budget_is_explicit(self):
        entered, release = threading.Event(), threading.Event()
        def sink(sample):
            entered.set()
            release.wait(2)
        worker = ConsumerDelivery(sink, 1, 2)
        try:
            worker.submit({})
            self.assertTrue(entered.wait(1))
            result = worker.close(0.01)
            self.assertEqual(result['error'], 'sample_consumer_shutdown_timeout')
        finally:
            release.set()
            worker.thread.join(1)

    def test_stale_queued_sample_is_rejected_before_callback(self):
        entered, release = threading.Event(), threading.Event()
        received = []
        def sink(sample):
            received.append(sample)
            entered.set()
            release.wait(1)
        worker = ConsumerDelivery(sink, 2, 1)
        try:
            worker.submit({'stream_index': 0})
            self.assertTrue(entered.wait(1))
            # Reproduce a backlog age violation without a wall-clock sleep.
            worker.queue.put_nowait((time.monotonic()-2, {'stream_index': 1}))
            worker.submitted += 1
            self.assertEqual(worker.check(), 'sample_consumer_stale')
        finally:
            release.set()
            worker.thread.join(1)
        self.assertEqual([r['stream_index'] for r in received], [0])

    def test_invalid_consumer_settings_do_not_create_file(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)/'data.jsonl'
            for options in ({'consumer_queue_size': 0}, {'consumer_timeout': float('nan')},
                            {'consumer_shutdown_timeout': -1}, {'sample_sink': 3}):
                with self.assertRaises(ValueError):
                    Pipeline(output, **options)
                self.assertFalse(output.exists())

    def test_unlimited_and_long_duration_accepted_without_hardware(self):
        with tempfile.TemporaryDirectory() as directory:
            capture = Path(directory)/'replay.json'
            from fixture_support import fixture_path
            original = json.loads(fixture_path('ble-capture.json').read_text())
            original['packets'] = []
            capture.write_text(json.dumps(original))
            for seconds in ('0', '100000'):
                result = subprocess.run([sys.executable, 'stream.py', '--replay', str(capture),
                                         '--output', str(Path(directory)/(seconds+'.jsonl')),
                                         '--seconds', seconds], capture_output=True, text=True)
                # Empty recording is deliberately not clean (exit 1), but parsed/run.
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertEqual(json.loads(result.stdout)['kind'], 'summary')


if __name__ == '__main__':
    unittest.main()
