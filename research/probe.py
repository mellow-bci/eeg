"""Discover EPOC X and record its GATT inventory. No device commands are written."""
import argparse
import asyncio
import json
from datetime import datetime, timezone
from pathlib import Path

from bleak import BleakClient, BleakScanner


async def probe(args):
    report = {"time": datetime.now(timezone.utc).isoformat(), "status": "scanning"}
    try:
        device = await BleakScanner.find_device_by_filter(
            lambda d, a: "EPOC" in (a.local_name or d.name or "").upper(),
            timeout=args.timeout,
        )
        if device is None:
            report["status"] = "not_found"
        else:
            report.update(name=device.name, address=device.address, status="connecting")
            print(f"Found {device.name}; connecting", flush=True)
            async with BleakClient(device, timeout=args.timeout) as client:
                report["services"] = [
                    {"uuid": s.uuid, "characteristics": [
                        {"uuid": c.uuid, "properties": c.properties, "handle": c.handle}
                        for c in s.characteristics
                    ]} for s in client.services
                ]
                report["status"] = "connected_inventory_captured"
    except Exception as exc:
        report.update(status="error", error_type=type(exc).__name__, error=str(exc))
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    Path(args.output).write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0 if report["status"] == "connected_inventory_captured" else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=float, default=15)
    parser.add_argument("--output", default="epoc-probe.json")
    raise SystemExit(asyncio.run(probe(parser.parse_args())))
