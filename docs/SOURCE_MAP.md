# Source map and authority

## Maintained root modules

| File | Responsibility |
|---|---|
| stream.py | Live/replay pipeline, consumer gate, watchdog, lease, CLI, persistence |
| decoder.py | Metadata gate, key derivation, decryption, packet validation, mapping, voltage conversion |
| contact_quality.py | Conservative raw CQ slot tracking; no quality classes |
| probe_connected.py | macOS read-only connected-peripheral listing |
| inspect_contact_quality.py | Offline CQ replay through the tracker |
| reference_csv.py | Documented CSV schema validation, not source identity validation |
| compare_paired.py | Parameterized same-sample comparison |
| analyze_signal.py | Descriptive longest-stable-segment signal statistics |
| fixture_support.py | Explicit fixture resolution and missing-fixture reporting |

## Offline tools

`tools/read_record.cpp` reconstructs the local file key reader and uses Apache
Parquet authenticated decryption. `tools/build_reader.py` builds it against
pyarrow libraries. `tools/extract_interval.py` extracts a supplied timestamp
interval without hardcoding a person's recording identity.

## Preserved research modules

| File under research/ | Historical/current experimental use |
|---|---|
| audible_eye_test.py | Spoken eye/blink protocol using Pipeline/live |
| analyze_blinks.py | Four-second cue-locked detrended RMS/peak-to-peak |
| compare_eye_phases.py | Trimmed eye-phase Welch power comparison |
| mark_phase.py | Manual phase marker helper |
| probe.py, capture.py | Initial BLE metadata/notification probes; not production entry points |
| check_legacy_framing.py | Rejected older-format exploration; no supported legacy decoder |
| analyze.py | Initial packet/transport diagnostics |

These files preserve the research state; some use top-level execution, positional
arguments, old field assumptions or replace analysis outputs. Read their source
and use copies of recordings. They are not all production-hardened merely because
the acquisition pipeline has newer safeguards.

## Complete archive

`archive/current-state/` preserves the original work directory byte-for-byte
(excluding bytecode caches). It includes its own scripts, timestamped files,
full reports and historical notes. Older notes are not current truth when they
contradict the current documentation. `docs/` and maintained root code take
precedence. The archive exists to retain every experiment and support audit.
