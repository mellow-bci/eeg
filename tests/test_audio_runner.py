"""No hardware or actual speech: exercise participant-cue failure paths."""
import asyncio
import argparse
import time
import unittest
from unittest.mock import patch
from calibration import run_audio


class PipelineStub:
    def __init__(self):
        self.transport_stable = True
        self.epoch = 1
        self.clock_origin = time.monotonic()
        self.rows = []
    def write(self, row):
        self.rows.append(row)


class AudioRunnerTests(unittest.IsolatedAsyncioTestCase):
    async def run_case(self, failure=None):
        pipeline = PipelineStub()
        cues = []
        trial_started = asyncio.Event()
        async def speak(text):
            cues.append(text)
            if text == 'Close your eyes now.':
                trial_started.set()
                if failure == 'during_speech':
                    await asyncio.sleep(.04)
        async def capture(*args):
            if failure:
                await trial_started.wait()
                await asyncio.sleep(.005)
                if failure in ('capture_error', 'during_speech'):
                    raise RuntimeError('BLE disconnected')
                if failure == 'capture_end':
                    return
                if failure == 'stale':
                    pipeline.transport_stable = False
                if failure == 'epoch':
                    pipeline.epoch += 1
            await asyncio.Event().wait()
        plan = {'protocol': 'test', 'events': [{'trial_id': 'one', 'label': 'closed',
                 'cue_text': 'Close your eyes now.', 'duration_seconds': .04}]}
        with patch.object(run_audio, 'say', speak), patch.object(run_audio, 'live', capture):
            if failure:
                with self.assertRaises(RuntimeError):
                    await run_audio.experiment(argparse.Namespace(device='fake'), pipeline, plan)
            else:
                await run_audio.experiment(argparse.Namespace(device='fake'), pipeline, plan)
        self.assertIn('Open your eyes now', cues[-1])
        self.assertEqual(any(r['kind'] == 'experiment_complete' for r in pipeline.rows), not bool(failure))
        if failure:
            self.assertFalse(any(r['kind'] == 'experiment_trial_end' for r in pipeline.rows))
        if failure == 'during_speech':
            self.assertFalse(any(r['kind'] == 'experiment_trial_start' for r in pipeline.rows))

    async def test_success_closes_with_open_eyes_cue(self):
        await self.run_case()
    async def test_capture_exception_during_final_trial_still_gives_cue(self):
        await self.run_case('capture_error')
    async def test_normal_capture_end_during_final_trial_aborts(self):
        await self.run_case('capture_end')
    async def test_stale_signal_aborts_final_trial(self):
        await self.run_case('stale')
    async def test_epoch_change_aborts_final_trial(self):
        await self.run_case('epoch')
    async def test_failure_during_speech_never_starts_trial(self):
        await self.run_case('during_speech')

    async def test_cancelled_experiment_gives_final_cue(self):
        cues = []
        trial = asyncio.Event()
        async def speak(text):
            cues.append(text)
            if text == 'Close eyes': trial.set()
        async def capture(*args): await asyncio.Event().wait()
        pipeline = PipelineStub()
        plan = {'protocol': 'test', 'events': [{'trial_id': 'x', 'label': 'closed',
                'cue_text': 'Close eyes', 'duration_seconds': 60}]}
        with patch.object(run_audio, 'say', speak), patch.object(run_audio, 'live', capture):
            task = asyncio.create_task(run_audio.experiment(argparse.Namespace(device='fake'), pipeline, plan))
            await trial.wait()
            task.cancel()
            with self.assertRaises(asyncio.CancelledError): await task
        self.assertIn('Open your eyes now', cues[-1])

    async def test_speech_timeout_terminates_process(self):
        class Process:
            returncode = None
            terminated = False
            async def wait(self):
                if self.terminated: return -15
                await asyncio.Event().wait()
            def terminate(self): self.terminated = True; self.returncode = -15
        process = Process()
        original_wait_for = asyncio.wait_for
        async def short_wait(awaitable, timeout):
            return await original_wait_for(awaitable, timeout=.01)
        async def spawn(*args): return process
        with patch.object(asyncio, 'create_subprocess_exec', spawn), patch.object(asyncio, 'wait_for', short_wait):
            with self.assertRaises(asyncio.TimeoutError): await run_audio.say('mock only')
        self.assertTrue(process.terminated)
