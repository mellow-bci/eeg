# End-to-end architecture

## Operational path

1. A desktop process receives macOS Bluetooth permission.
2. `stream.py` holds an advisory per-device lease, resolves a known connected CoreBluetooth peripheral or discovers an advertising headset.
3. `live()` reads serial, software revision and configuration; it never writes firmware/configuration.
4. `BleakClient` subscribes to the EEG characteristic. Every notification is written to JSONL before decoding.
5. `Decoder.decode()` validates framing, decrypts and produces raw ADC samples plus optional vendor-scaled volts and raw auxiliary bytes.
6. `Pipeline.packet()` tracks continuity, arrival timing, recovery state and stable segments.
7. All decoded samples remain in the audit recording. An optional synchronous `sample_sink` receives deep copies only when transport is stable and the supported voltage configuration is present.
8. The watchdog handles silence/disconnect; a completed run writes and fsyncs a summary.

The production-direction dependency is headset → OS Bluetooth → Bleak → our decoder → our pipeline. Vendor binaries, account credentials, Cortex APIs and recovered Parquet files are **not runtime dependencies** of the reader.

## Independent reference path

During validation only, Cortex and our reader receive the same connection on the same Mac. Cortex writes its local encrypted device-session data. A copied, authenticated recovery produces a reference table, which `compare_paired.py` matches against the direct capture using all 14 channel ADC values and counters. The matching result is separate from live readiness flags.

## Separation of concerns

- The agent/UI/application layer is not implemented here. No sample triggers an action.
- Transport stability means recent contiguous packets, not good scalp contact.
- Vendor-equivalent scaling means matching Cortex conversion, not calibration against a physical laboratory reference.
- Descriptive blink/eye analysis is not a neural classifier.
- `research/` preserves experiments, including earlier acquisition probes. Only the root `stream.py` is the recommended live entry point.
- `archive/current-state/` is an immutable historical work snapshot. Its duplicated source and stale notes are evidence, not another maintained implementation. Root code and current `docs/` are authoritative.
