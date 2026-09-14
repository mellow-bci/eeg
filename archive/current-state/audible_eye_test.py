"""Spoken, timestamped eye cues using the existing direct acquisition pipeline.

Run only after the participant confirms the Mac's audio check is audible.
Markers time local playback completion, not measured eyelid movement.
"""
import argparse,asyncio,json,time
from pathlib import Path
from types import SimpleNamespace
from datetime import datetime,timezone
from stream import Pipeline,live

PHASES=[('eyes_open_1',20,'The test is starting. Keep your eyes open. Sit still and do not speak.'),
        ('eyes_closed_1',30,'Close your eyes gently now. Keep still. I will tell you when to open them.'),
        ('eyes_open_2',20,'Open your eyes now. Keep still and stay relaxed.'),
        ('eyes_closed_2',30,'Close your eyes gently again. Keep still.'),
        ('eyes_open_3',20,'Open your eyes now. This is the final recording period. Keep still.')]

async def speak(pipeline,text):
    pipeline.write({'kind':'audio_cue','stage':'playback_requested',
                    't':time.monotonic()-pipeline.clock_origin,'text':text})
    process=await asyncio.create_subprocess_exec('/usr/bin/say',text)
    try:
        await asyncio.wait_for(process.wait(),timeout=20)
        if process.returncode:raise RuntimeError('Speech playback process failed')
    finally:
        if process.returncode is None:
            process.terminate();await process.wait()
    pipeline.write({'kind':'audio_cue','stage':'playback_process_completed',
                    't':time.monotonic()-pipeline.clock_origin,'text':text})

async def run(output, device=None, protocol="eyes"):
    phases = PHASES if protocol == "eyes" else [("baseline",20,"The blink test is starting. Keep your head still and stay relaxed. When I say blink, blink twice, then relax. Wait for the cue.")] + [("blink_"+str(i),12,"Blink twice now.") for i in range(1,7)] + [("rest",10,"Keep still and relax. No more deliberate blinks.")]
    pipeline=Pipeline(output)
    markers=Path(output).with_suffix('.markers.jsonl').open('x')
    task=asyncio.create_task(live(SimpleNamespace(device=device,seconds=220,attempts=2),pipeline))
    completed=False
    try:
        deadline=time.monotonic()+60
        while not pipeline.transport_stable:
            if task.done() or time.monotonic()>deadline:raise RuntimeError('No stable headset stream; eye test not started')
            await asyncio.sleep(.1)
        epoch=pipeline.epoch
        def check_stream():
            if task.done() or pipeline.epoch!=epoch or not pipeline.transport_stable:
                raise RuntimeError('Stream interrupted during eye test')
        def mark(name):
            marker={'phase':name,'latest_sample_host_time':time.monotonic()-pipeline.clock_origin,
                    'cue_logged_utc':datetime.now(timezone.utc).isoformat(),
                    'timing_basis':'local_speech_process_completed_monotonic_clock',
                    'participant_compliance_verified':False}
            markers.write(json.dumps(marker)+'\n');markers.flush()
            pipeline.write(dict(marker,kind='test_phase'))
            print(json.dumps(marker),flush=True)
        for name,duration,cue in phases:
            check_stream()
            pipeline.write({"kind":"phase_cue_onset","phase":name,"t":time.monotonic()-pipeline.clock_origin,"timing_basis":"before_speech_process_start"})
            await speak(pipeline,cue);check_stream();mark(name)
            end=time.monotonic()+duration
            while time.monotonic()<end:
                check_stream();await asyncio.sleep(min(.1,max(.001,end-time.monotonic())))
        mark('test_complete')
        await speak(pipeline,'The test is complete. Keep your eyes open. You can relax normally now. Thank you.')
        completed=True
    except Exception as exc:
        pipeline.write({'kind':'test_error','message':str(exc)})
        await speak(pipeline,'The test has stopped. Open your eyes now. You can relax normally.')
        print(str(exc),flush=True)
    finally:
        task.cancel()
        try:await task
        except asyncio.CancelledError:pass
        pipeline.write({'kind':'test_outcome','protocol_completed':completed,
                        'participant_compliance_verified':False})
        markers.close();summary=pipeline.finish();print(json.dumps(summary),flush=True)
    return 0 if completed else 1

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',required=True)
    parser.add_argument('--device', help='Previously discovered CoreBluetooth identifier')
    parser.add_argument("--protocol", choices=("eyes","blinks"), default="eyes")
    args=parser.parse_args();raise SystemExit(asyncio.run(run(args.output,args.device,args.protocol)))
