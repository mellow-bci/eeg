from fixture_support import fixture_path
"""Replay-backed pipeline boundary tests; these do not simulate hardware proof."""
import json
import tempfile
import unittest
from pathlib import Path
from stream import Pipeline


class PipelineTests(unittest.TestCase):
    def test_reconnect_preserves_identity_and_indices(self):
        capture = json.loads(fixture_path('ble-capture.json').read_text())
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'stream.jsonl'
            pipeline = Pipeline(path)
            for _ in range(2):
                pipeline.configure(capture['info'], 'recorded_ble_replay')
                pipeline.packet(capture['packets'][0])
            summary = pipeline.finish()
            rows = [json.loads(line) for line in path.read_text().splitlines()]
        samples = [r for r in rows if r['kind'] == 'eeg_adc']
        self.assertEqual([r['epoch'] for r in samples], [1, 1, 2, 2])
        self.assertEqual([r['stream_index'] for r in samples], [0, 1, 2, 3])
        self.assertEqual([r['index'] for r in samples], [0, 1, 0, 1])
        self.assertEqual(summary['samples'], 4)
        self.assertEqual(len(summary['connection_epochs']), 2)

    def test_existing_capture_never_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'existing.jsonl'
            path.write_text('original')
            with self.assertRaises(FileExistsError):
                Pipeline(path)
            self.assertEqual(path.read_text(), 'original')

class RealReconnectTests(unittest.TestCase):
    def test_startup_errors_remain_visible_and_stream_recovers(self):
        path = fixture_path('live-reconnect-20260914T181253Z.jsonl')
        rows = [json.loads(line) for line in path.read_text().splitlines()]
        with tempfile.TemporaryDirectory() as directory:
            pipeline = Pipeline(Path(directory) / 'replay.jsonl')
            pipeline.configure(next(r['info'] for r in rows if r['kind']=='stream_start'), 'recorded_ble_replay')
            for row in rows:
                if row['kind']=='ble_notification':
                    pipeline.packet(row)
            summary = pipeline.finish()
        self.assertEqual(summary['decode_errors'], 2)
        self.assertEqual(summary['counter_discontinuities'], 1)
        self.assertFalse(summary['capture_clean'])
        self.assertTrue(summary['transport_stable_at_end'])
        self.assertEqual(summary['samples'], 1338)


class StableConsumerTests(unittest.TestCase):
    def test_real_paired_startup_is_excluded_and_reconnect_splits_segments(self):
        rows = [json.loads(line) for line in fixture_path('epoc-paired-20260915-02.jsonl').read_text().splitlines()]
        info = next(r['info'] for r in rows if r['kind']=='stream_start')
        delivered = []
        with tempfile.TemporaryDirectory() as directory:
            p = Pipeline(Path(directory)/'replay.jsonl', sample_sink=delivered.append)
            for _ in range(2):
                p.configure(info, 'recorded_ble_replay')
                for r in rows:
                    if r['kind']=='ble_notification': p.packet(r)
            summary=p.finish()
        self.assertEqual(len(delivered), 3582*2)
        self.assertEqual(summary['samples'], 3858*2)
        self.assertEqual(summary['counter_discontinuities'], 4)
        self.assertFalse(summary['capture_clean'])
        self.assertEqual({r['stable_segment'] for r in delivered}, {1,2})
        self.assertTrue(all(r['transport_stable'] for r in delivered))
        self.assertTrue(all(r['index']>=31 for r in delivered))
        for a,b in zip(delivered, delivered[1:]):
            if a['stable_segment']==b['stable_segment']:
                self.assertEqual((a['counter']+1)%128, b['counter'])


class FailureBoundaryTests(unittest.TestCase):
    def replay_rows(self):
        return [json.loads(l) for l in fixture_path('epoc-paired-20260915-02.jsonl').read_text().splitlines()]

    def test_wrapping_counters_do_not_hide_arrival_gap(self):
        rows=self.replay_rows();delivered=[]
        with tempfile.TemporaryDirectory() as directory:
            p=Pipeline(Path(directory)/'capture.jsonl', sample_sink=delivered.append)
            p.configure(next(r['info'] for r in rows if r['kind']=='stream_start'),'replay')
            packets=[r for r in rows if r['kind']=='ble_notification']
            for i,r in enumerate(packets):
                r=dict(r)
                if i>=400:r['t']+=1.0
                before=len(delivered);p.packet(r)
                if i==400:
                    self.assertFalse(p.transport_stable)
                    self.assertEqual(before,len(delivered))
            p.finish()
        self.assertEqual({r['stable_segment'] for r in delivered},{1,2})

    def test_missing_configuration_never_delivers_calibrated_samples(self):
        from decoder import CONFIG_CHARACTERISTIC
        rows=self.replay_rows();delivered=[]
        info=dict(next(r['info'] for r in rows if r['kind']=='stream_start'))
        info.pop(CONFIG_CHARACTERISTIC)
        with tempfile.TemporaryDirectory() as directory:
            p=Pipeline(Path(directory)/'capture.jsonl',sample_sink=delivered.append)
            p.configure(info,'replay')
            for r in rows:
                if r['kind']=='ble_notification':p.packet(r)
            summary=p.finish()
        self.assertGreater(summary['stable_samples'],0)
        self.assertEqual(delivered,[])

    def test_consumer_failure_is_fatal_and_not_a_clean_capture(self):
        from stream import AcquisitionFailure
        rows=self.replay_rows()
        def fail(sample):raise RuntimeError('Consumer unavailable')
        with tempfile.TemporaryDirectory() as directory:
            p=Pipeline(Path(directory)/'capture.jsonl',sample_sink=fail)
            p.configure(next(r['info'] for r in rows if r['kind']=='stream_start'),'replay')
            with self.assertRaises(AcquisitionFailure):
                for r in rows:
                    if r['kind']=='ble_notification':p.packet(r)
            summary=p.finish()
        self.assertFalse(summary['capture_clean'])
        self.assertFalse(summary['transport_stable_at_end'])
        self.assertEqual(summary['fatal_error'],'sample_consumer_failed')

    def test_capture_file_is_private_and_storage_failure_is_fatal(self):
        from stream import AcquisitionFailure
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'capture.jsonl';p=Pipeline(path)
            self.assertEqual(path.stat().st_mode & 0o777,0o600)
            p.file.close()
            with self.assertRaises(AcquisitionFailure):p.write({'kind':'test'})
            self.assertEqual(p.fatal_error,'capture_storage_failed')


class LeaseTests(unittest.TestCase):
    def test_duplicate_reader_rejected_and_lease_released(self):
        from stream import DeviceLease, AcquisitionFailure
        with tempfile.TemporaryDirectory() as directory:
            with DeviceLease('DEVICE',directory):
                with self.assertRaises(AcquisitionFailure):
                    with DeviceLease('device',directory):pass
            with DeviceLease('device',directory):pass


class FreshnessTests(unittest.TestCase):
    def test_silence_revokes_readiness_before_next_packet(self):
        rows=[json.loads(l) for l in fixture_path('epoc-paired-20260915-02.jsonl').read_text().splitlines()]
        with tempfile.TemporaryDirectory() as directory:
            p=Pipeline(Path(directory)/'capture.jsonl')
            p.configure(next(r['info'] for r in rows if r['kind']=='stream_start'),'replay')
            for r in rows:
                if r['kind']=='ble_notification':p.packet(r)
                if p.transport_stable:break
            self.assertTrue(p.transport_stable)
            p.check_freshness(p.last_packet_at+0.6)
            self.assertFalse(p.transport_stable)
            p.check_freshness(p.last_packet_at+0.7)
            path=Path(directory)/'capture.jsonl'
            p.finish()
            events=[json.loads(l) for l in path.read_text().splitlines()]
            self.assertEqual(sum(e.get('reason')=='stale_input' for e in events),1)


class WatchdogTests(unittest.IsolatedAsyncioTestCase):
    async def test_silent_connected_transport_is_reported_as_failure(self):
        import sys
        from types import SimpleNamespace
        from unittest.mock import patch
        from stream import live
        from decoder import CONFIG_CHARACTERISTIC
        capture = json.loads(fixture_path('ble-capture.json').read_text())
        class SilentClient:
            address = 'test-transport'
            def __init__(self, *args, **kwargs): pass
            async def __aenter__(self): return self
            async def __aexit__(self, *args): pass
            async def read_gatt_char(self, uuid):
                if uuid == CONFIG_CHARACTERISTIC: return bytes.fromhex('018000102010')
                return bytes.fromhex(capture['info'][uuid]['hex'])
            async def start_notify(self, *args): pass
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'watchdog.jsonl'
            pipeline = Pipeline(path)
            with patch.dict(sys.modules, {'bleak': SimpleNamespace(BleakClient=SilentClient, BleakScanner=None)}), patch('stream.connected_device', side_effect=lambda address: address):
                await live(SimpleNamespace(device='test-transport', seconds=6, attempts=1), pipeline)
            summary = pipeline.finish()
            rows = [json.loads(line) for line in path.read_text().splitlines()]
        self.assertEqual(summary['samples'], 0)
        self.assertFalse(summary['capture_clean'])
        self.assertEqual(summary['transport_interruptions'], 1)
        self.assertEqual(summary['connection_errors'], 1)
        self.assertTrue(any(r.get('reason')=='notification_timeout' for r in rows))


class CallbackFailureTests(unittest.IsolatedAsyncioTestCase):
    async def test_notification_failure_is_not_swallowed_or_retried(self):
        import sys
        from types import SimpleNamespace
        from unittest.mock import patch
        from stream import live, AcquisitionFailure
        from decoder import CONFIG_CHARACTERISTIC, DATA_CHARACTERISTIC
        capture=json.loads(fixture_path('ble-capture.json').read_text())
        connects=[]
        class Client:
            address='test-transport'
            def __init__(self,*args,**kwargs):connects.append(1)
            async def __aenter__(self):return self
            async def __aexit__(self,*args):pass
            async def read_gatt_char(self,uuid):
                if uuid==CONFIG_CHARACTERISTIC:return bytes.fromhex('018000102010')
                return bytes.fromhex(capture['info'][uuid]['hex'])
            async def start_notify(self,uuid,callback):
                callback(SimpleNamespace(uuid=DATA_CHARACTERISTIC),bytes.fromhex(capture['packets'][0]['hex']))
        with tempfile.TemporaryDirectory() as directory:
            p=Pipeline(Path(directory)/'capture.jsonl')
            with patch.dict(sys.modules,{'bleak':SimpleNamespace(BleakClient=Client,BleakScanner=None)}), patch('stream.connected_device',side_effect=lambda x:x), patch.object(p,'packet',side_effect=OSError('disk full')):
                with self.assertRaises(AcquisitionFailure):
                    await live(SimpleNamespace(device='test-transport',seconds=6,attempts=3),p)
            summary=p.finish()
        self.assertEqual(len(connects),1)
        self.assertFalse(summary['capture_clean'])
        self.assertEqual(summary['fatal_error'],'notification_processing_failed')


class RecordingBudgetTests(unittest.TestCase):
    def test_budget_exhaustion_is_explicit_and_does_not_exceed_limit(self):
        from stream import AcquisitionFailure
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'capture.jsonl';p=Pipeline(path,max_bytes=80)
            p.write({'kind':'test'})
            with self.assertRaises(AcquisitionFailure):p.write({'kind':'test','data':'x'*100})
            self.assertEqual(p.fatal_error,'capture_size_limit')
            self.assertLessEqual(path.stat().st_size,80)
            with self.assertRaises(AcquisitionFailure):p.finish()
            self.assertTrue(p.file.closed)


if __name__ == '__main__':
    unittest.main()
