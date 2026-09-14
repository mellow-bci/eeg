# Operations and troubleshooting

## Setup

1. Clone the private repository and run `git lfs pull`.
2. Create an isolated Python environment and install pinned requirements.txt.
3. Use a desktop Terminal on the Mac physically receiving Bluetooth. SSH process
   authorization may differ from desktop authorization.
4. Grant Bluetooth permission normally. Do not patch macOS privacy databases.
5. Power on EPOC X. For scalp-signal tests, prepare sensors and fit the headset;
   transport/framing tests do not require wearing it.
6. Run `probe_connected.py` to list connected EPOC peripherals. Copy the ID from
   that host; never reuse a different Mac's CoreBluetooth ID by assumption.
7. Create `recordings/` and use the root stream.py CLI. Output must be a new path.

```sh
mkdir -p recordings
.venv/bin/python stream.py --device LOCAL-ID --seconds 120 --attempts 3 --max-bytes 536870912 --output recordings/capture-001.jsonl
```

Supported duration is positive and at most 3600 seconds per attempt; retries and
cycles can extend overall wall-clock time. Attempts/cycles are bounded at 10.
Use `--cycles` only for deliberate lifecycle testing. No background service or
cloud deployment is installed by this repository.

## M3/M4 observations

The implementation host and physical-device host differed during work. M4 ran
the official app and same-input comparison; M3 held the initial source/analysis.
macOS returned unauthorized for the SSH-launched probe; launching the same probe
in desktop Terminal succeeded. A transient initial “Bluetooth off” error was
followed by a successful probe while system inventory showed Bluetooth on.
Hostnames/IDs and personal serials remain in private original evidence.

## Failure interpretation

| Symptom | Action / interpretation |
|---|---|
| BLE unauthorized | Check permission for the actual desktop process; do not assume app permission transfers |
| Known ID not found while Cortex connected | Use current connected-peripheral resolution on that host |
| Wrong revision/type/length | Preserve bytes; stop guessing protocol variants |
| Startup counter errors | Retain/quarantine; wait for stable gate, do not relax checks |
| Silent connection | Readiness revokes at 0.5 s; five-second watchdog attempts recovery |
| Consumer exception | Fatal acquisition failure; repair consumer, not Bluetooth |
| Disk/budget failure | Stop; inspect incomplete file, allocate new output and capacity |
| Missing summary | Capture is incomplete; do not infer success from partial rows |
| CQ raw changing | Not sufficient to display a validated good/poor-contact class |
| Ctrl-C/SIGTERM | Graceful shutdown attempted; inspect summary/fatal result |

Research analyses can load whole files into memory; acquisition itself streams
events. Avoid running unbounded research analyses in the acquisition process.
For release work, measure latency and memory externally, record source version,
hardware metadata, exact start/end, process lifecycle and anomalies.
