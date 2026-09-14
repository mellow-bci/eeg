"""Run an explicitly requested local audio-cued experiment alongside direct BLE.

Run on the headset Mac from a desktop Terminal with Bluetooth permission.
Uses the repository's single acquisition pipeline; no classifier or actions.
"""
import argparse, asyncio, json, os, signal, sys, time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from stream import Pipeline,live,DeviceLease

async def say(text):
    process=await asyncio.create_subprocess_exec('/usr/bin/say',text)
    try:
        if await asyncio.wait_for(process.wait(), timeout=20)!=0:raise RuntimeError('Audio cue process failed')
    finally:
        if process.returncode is None:
            process.terminate()
            try: await asyncio.wait_for(process.wait(), timeout=2)
            except asyncio.TimeoutError:
                process.kill();await process.wait()

async def experiment(args,pipeline,manifest):
    capture_args=argparse.Namespace(device=args.device,attempts=1,seconds=600)
    capture=asyncio.create_task(live(capture_args,pipeline))
    try:
        deadline=time.monotonic()+45
        while not pipeline.transport_stable:
            if capture.done():await capture;raise RuntimeError('Capture ended before stability')
            if time.monotonic()>deadline:raise RuntimeError('No stable signal within 45 seconds; no trials run')
            await asyncio.sleep(.1)
        initial_epoch = pipeline.epoch

        async def check_capture():
            if capture.done():
                await capture
                raise RuntimeError('Acquisition ended during experiment')
            if not pipeline.transport_stable or pipeline.epoch != initial_epoch:
                raise RuntimeError('Signal interrupted; trial is unusable')

        async def guarded(awaitable):
            # Monitor during speech as well as trial dwell; do not wait until
            # the next trial to discover that the participant has no valid data.
            operation = asyncio.create_task(awaitable)
            try:
                while not operation.done():
                    await check_capture()
                    await asyncio.wait({operation}, timeout=.1)
                await check_capture()
                return await operation
            finally:
                if not operation.done():
                    operation.cancel()
                try: await operation
                except asyncio.CancelledError: pass

        await guarded(say('The EEG test is beginning. Follow each spoken cue. Stay comfortable and avoid moving your head. You can stop at any time.'))
        for event in manifest['events']:
            await check_capture()
            onset=time.monotonic()-pipeline.clock_origin
            pipeline.write({'kind':'experiment_cue','t':onset,'event':event,'compliance_verified':False})
            await guarded(say(event['cue_text']))
            start=time.monotonic()-pipeline.clock_origin
            pipeline.write({'kind':'experiment_trial_start','t':start,'trial_id':event['trial_id'],'label':event['label'],'compliance_verified':False})
            await guarded(asyncio.sleep(event['duration_seconds']))
            pipeline.write({'kind':'experiment_trial_end','t':time.monotonic()-pipeline.clock_origin,'trial_id':event['trial_id'],'label':event['label'],'compliance_verified':False})
        await check_capture()
        pipeline.write({'kind':'experiment_complete','t':time.monotonic()-pipeline.clock_origin,'protocol':manifest['protocol'],'compliance_verified':False})
    finally:
        capture.cancel()
        try:
            try: await capture
            except asyncio.CancelledError: pass
        finally:
            # A previously failed capture raises when awaited. The final cue
            # must nevertheless run, including during participant cancellation.
            await say('The test has stopped. Open your eyes now. You can relax.')

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--plan',required=True);p.add_argument('--device',required=True);p.add_argument('--output',required=True);p.add_argument('--run',action='store_true');a=p.parse_args()
    if not a.run:p.error('Explicit --run is required after participant confirms readiness and audible cues')
    plan=json.loads(Path(a.plan).read_text())
    if plan.get('schema_version')!='eeg.calibration.protocol.v1':p.error('Unsupported plan')
    pipeline=Pipeline(a.output,max_bytes=512*1024*1024)
    def stop(*_):raise KeyboardInterrupt
    signal.signal(signal.SIGTERM,stop)
    try:
        pipeline.write({'kind':'experiment_plan','plan':plan})
        with DeviceLease(a.device):asyncio.run(experiment(a,pipeline,plan))
    except BaseException as exc:
        pipeline.write({'kind':'experiment_aborted','error':str(exc),'type':type(exc).__name__})
        raise
    finally:
        print(json.dumps(pipeline.finish()),flush=True)
if __name__=='__main__':main()
