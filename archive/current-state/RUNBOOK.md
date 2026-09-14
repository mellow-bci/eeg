# EPOC X acquisition operations

Status: acquisition validation build; production release gates are tracked in
PRODUCTION_READINESS.md. Tested on the user's macOS hosts with EPOC X software
revision 0740 and read-only device configuration 018000102010. No firmware writes.

## Installation and permissions

Create an isolated Python 3.9 environment, then install requirements.txt. The
PyObjC 11.1 pins are required for the tested Python version. Use a local desktop
Terminal on the Mac physically connected by Bluetooth. Grant Bluetooth access
through macOS when prompted. An SSH-launched interpreter may be unauthorized
although the same program works from desktop Terminal. Never alter the TCC DB.

Run probe_connected.py from that desktop environment to obtain the local
CoreBluetooth ID. IDs differ across Macs. If disconnected, stream.py can discover
the EPOCX advertisement by omitting --device; explicit device selection is preferred.

## One acquisition entry point

python stream.py --device LOCAL-COREBLUETOOTH-ID --seconds 180 --attempts 3 --output NEW-CAPTURE.jsonl

Existing output files are never replaced. Recordings are created mode 0600.
The per-device advisory lease prevents duplicate instances of this reader using
the same explicit ID. It does not lock other apps or equate discovery with every
possible explicit device ID. Production callers should require an explicit ID.

Cortex was run concurrently only to validate identical samples. It is not needed
by the decoder; exclusive standalone lifecycle qualification remains a release gate.

Ctrl-C ends capture and preserves a shutdown record when storage remains writable.
A failed, interrupted or anomalous capture must not be represented as clean.
Do not start a second writer against an existing capture file.

## Consuming data

Embed Pipeline(output, sample_sink=callback) in the same acquisition path. The
callback receives only transport-stable samples with verified supported device
configuration. Consumer eligibility is NOT proof of physiological signal quality.
Respect epoch and stable_segment boundaries; do not stitch across them. Apply a
separate stale-data timeout. Callbacks are synchronous and must not block. A
callback error is fatal, rather than treated as a reconnectable Bluetooth error.

All raw frames, decode errors and unstable samples remain in JSONL. A >0.5-second
arrival gap resets stability even if the 7-bit counter appears continuous. The
5-second notification watchdog reconnects a silent connection. Two seconds and
256 contiguous samples are required to regain stable status.

The BLE payload format has no verified cryptographic authentication. Validation
checks and same-sample agreement do not turn ECB data into authenticated transport.

## Validation and limitations

Run: python -m unittest discover -s . -p 'test_*.py' -q

Tests use real saved packet fixtures and explicitly synthetic failure injection.
Vendor reference recovery and comparison are offline validation utilities. They
are not runtime dependencies and are not a replacement for independently testing
contact-quality classes or BCI intent models. See VALIDATION.md for provenance.

Recordings default to a 512 MiB hard budget (--max-bytes). Exceeding it fails
explicitly; no silent dropping or overwriting. SIGTERM follows the same shutdown
path as Ctrl-C. A completed summary is fsynced before closing. Readiness expires
after 0.5 seconds of silence, separately from the five-second reconnect watchdog.
