"""Capture EPOC BLE notifications without sending device commands."""
import argparse
import asyncio
import json
import time
from datetime import datetime, timezone
from pathlib import Path
from bleak import BleakClient, BleakScanner

SERVICE = '81072f40-9f3d-11e3-a9dc-0002a5d5c51b'

async def capture(args):
    report = {'time': datetime.now(timezone.utc).isoformat(), 'worn': False,
              'status': 'scanning', 'info': {}, 'packets': [], 'decoded': False}
    started = time.monotonic()
    try:
        device = await BleakScanner.find_device_by_filter(
            lambda d, a: 'EPOCX' in (a.local_name or d.name or '').upper(), timeout=12)
        if device is None:
            report['status'] = 'not_found'
            return report
        report.update(name=device.name, address=device.address)
        async with BleakClient(device, timeout=15) as client:
            def notification(c, data):
                report['packets'].append({'t': time.monotonic()-started,
                                          'uuid': c.uuid, 'hex': bytes(data).hex()})
            for service in client.services:
                if service.uuid == SERVICE or service.uuid.startswith(('0000180a-', '0000180f-')):
                    for c in service.characteristics:
                        if 'read' in c.properties:
                            try:
                                report['info'][c.uuid] = bytes(await client.read_gatt_char(c)).hex()
                            except Exception as exc:
                                report['info'][c.uuid] = {'error': str(exc)}
                if service.uuid == SERVICE:
                    for c in service.characteristics:
                        if 'notify' in c.properties:
                            await client.start_notify(c, notification)
            await asyncio.sleep(args.seconds)
            report['status'] = 'captured' if report['packets'] else 'connected_no_packets'
    except Exception as exc:
        report.update(status='error', error=str(exc))
    finally:
        Path(args.output).write_text(json.dumps(report, indent=2)+'\n')
    return report

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--seconds', type=float, default=15)
    p.add_argument('--output', default='capture.json')
    args = p.parse_args()
    if not 0 < args.seconds <= 60:
        p.error('seconds must be between 0 and 60')
    r = asyncio.run(capture(args))
    print(json.dumps({'status': r['status'], 'packets': len(r['packets']), 'output': args.output}))
    raise SystemExit(0 if r['status'] == 'captured' else 1)
