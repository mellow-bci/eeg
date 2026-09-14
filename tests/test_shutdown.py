from fixture_support import fixture_path
"""Subprocess shutdown test with an explicitly fake Bluetooth transport."""
import json, os, signal, subprocess, sys, tempfile, time, unittest
from pathlib import Path

class ShutdownTests(unittest.TestCase):
    def test_sigterm_writes_shutdown_and_summary(self):
        root=Path(__file__).resolve().parents[1]
        fixture_path('ble-capture.json')
        code=r'''
import asyncio,json,sys
from pathlib import Path
from types import SimpleNamespace
import stream
from decoder import CONFIG_CHARACTERISTIC
from fixture_support import fixture_path
capture=json.loads(fixture_path('ble-capture.json').read_text())
class Client:
    address='synthetic-shutdown-test'
    def __init__(self,*args,**kwargs):pass
    async def __aenter__(self):return self
    async def __aexit__(self,*args):pass
    async def read_gatt_char(self,uuid):
        if uuid==CONFIG_CHARACTERISTIC:return bytes.fromhex('018000102010')
        return bytes.fromhex(capture['info'][uuid]['hex'])
    async def start_notify(self,*args):pass
sys.modules['bleak']=SimpleNamespace(BleakClient=Client,BleakScanner=None)
stream.connected_device=lambda address:address
raise SystemExit(stream.main())
'''
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'shutdown.jsonl'
            p=subprocess.Popen([sys.executable,'-c',code,'--output',str(path),
                '--device','synthetic-shutdown-test','--seconds','30','--attempts','1'],
                cwd=root,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            try:
                deadline=time.monotonic()+5
                while time.monotonic()<deadline:
                    if path.exists() and 'stream_start' in path.read_text():break
                    if p.poll() is not None:self.fail(p.communicate())
                    time.sleep(0.02)
                else:self.fail('fake transport did not initialize')
                p.send_signal(signal.SIGTERM)
                out,err=p.communicate(timeout=5)
                self.assertNotIn('Traceback',err)
                rows=[json.loads(l) for l in path.read_text().splitlines()]
                self.assertTrue(any(r.get('kind')=='shutdown' and r.get('reason')=='operator_stop' for r in rows))
                self.assertEqual(rows[-1]['kind'],'summary')
                self.assertFalse(rows[-1]['transport_stable_at_end'])
                self.assertFalse(rows[-1]['capture_clean'])
            finally:
                if p.poll() is None:p.kill()
                p.communicate()
