# EPOC X acquisition validation — 2026-09-14

## Hardware observations

| Capture | Result | Limits |
|---|---|---|
| live-blinks-discovery-20260914T185827Z.jsonl | Six spoken blink trials; 17,300 samples; zero errors/gaps; AF4 post/pre detrended RMS 4.33–6.24 across six trials | Cue-associated frontal response consistent with ocular artifact; no measured blink timing, sham controls, or independent decoder reference |
| live-audible-direct-20260914T184711Z.jsonl | Spoken five-phase worn test; 19,340 samples; zero errors/gaps; ~128.101 Hz; all analyzed segments stable | Eye-state compliance not measured; no repeatable closed-eye alpha increase; physiological result inconclusive |
| live-charged-20260914T181205Z.jsonl | 30 s; 3,840 samples; no errors/gaps; ~128.054 Hz | Off-head; no physiological validation |
| live-reconnect-20260914T181253Z.jsonl | Reconnected; 1,338 accepted samples; 2 rejected packets and 1 gap during startup | Original packets retained; not a clean capture |
| live-soak-20260914T181549Z.jsonl | 120 s; 15,424 samples; 1 rejected packet and 2 gaps confined to first ~0.1 s | Does not establish long-term reliability |
| live-cycles-20260914T181807Z.jsonl | Three successful reconnect cycles; 7,848 samples; every epoch reached stable state | 3 rejected packets and 5 gaps total at startup; intentional disconnects only |

Configuration read directly from characteristic 81072f44: 018000102010.
The verified EEG resolution is 16 bits. The exact configuration enables the
vendor's ADC / 7.8 microvolt conversion, with no invented offset or filtering.
Original ADC counts and BLE payloads remain preserved.

## Completed software work

- Independent direct BLE acquisition, V4 decryption and electrode mapping.
- Device metadata and configuration captured before acquisition.
- Conservative raw packet rejection, explicit discontinuities and recovery state.
- Stable transport gate after two seconds and at least 256 contiguous samples.
- Bounded reconnect attempts and notification-silence watchdog.
- Separate connection epochs and sample identities; no rate across outages.
- Append-only capture creation that never overwrites earlier files.
- Regression coverage using real captures; simulated silence-watchdog coverage.

## Still required before calling this a validated EEG/BCI system

- Independently compare voltage and channel values against reference data.
- Worn-headset contact and controlled physiological/artifact validation.
- Unexpected disconnect/radio-loss recovery on physical hardware.
- Longer stability runs and validation across supported devices/firmware.
- Contact-quality interpretation, signal processing, user calibration, intent
  inference and CAST/Apple HID integration. These are not implemented yet.

The user confirmed they are not wearing the headset during these tests.
Do not call off-head values physiological EEG or infer intended actions from them.

Final updated-code run `live-final-20260914T181959Z.jsonl`: 2614 accepted samples,
2288 marked transport-stable, two startup rejected packets and one gap.
No connection errors or notification-silence interruptions; capture_clean=false.
All 14 software tests passed after the final code changes.

## Worn controlled-cue capture

`live-controlled-20260914T183707Z.jsonl`: 150 seconds, 19,216 samples,
zero decoding errors/counter gaps. Central approximately 20-second segments
for each cued eye state were contiguous and transport-stable. Absolute
8–13 Hz power did not consistently rise in the cued eyes-closed interval.
The comparison is inconclusive; participant cue compliance was not measured.
Sidecar markers and phase-analysis JSON preserve timing and numeric results.
Contact/reference and physiological validation remain outstanding.

### TEST24 local recording recovery — 2026-09-15

Recovered the user's TEST24 interval from a copy of the official Cortex encrypted
Parquet device-session file. Original file and vendor applications unchanged.
This is local file recovery, not an official EMOTIVPRO export.

- Standard Parquet authenticated decryption succeeded: 22,424 source rows.
- Logged TEST24 timestamps selected 14,109 EEG samples, 14 channels, 128 Hz.
- Zero counter discontinuities and zero interpolated samples.
- All exported per-electrode CQ values are 4; overall CQ is 100.
- A deliberately corrupted disposable copy failed authenticated decryption and
  produced no output. Original source was never altered.
- All 19 existing regression tests pass.
- Artifacts: reference-test24/TEST24-recovered.csv, recovery-report.json,
  authentication-negative-check.json, read_record.cpp and extract_test24.py.
- This recording is different from the direct BLE blink recording. It does not
  establish sample-for-sample decoder agreement or validate CQ thresholds across
  different contact levels. Direct decoder validation remains incomplete.


### Simultaneous Cortex comparison — 2026-09-15

M4 desktop Terminal launch obtained Bluetooth access. The existing stream now
resolves the exact already-connected CoreBluetooth peripheral before scanning.
Thirty-second parallel capture: epoc-paired-20260915-02.jsonl, 3,858 samples,
zero decode errors, two startup counter discontinuities; capture_clean=false.

Recovered active Cortex session using a copy of its data plus footer sidecar;
authenticated Parquet read succeeded (192,000 reference rows). Matching requires
counter plus all 14 ADC electrode values, with no ambiguous matches accepted.
3,845 full-vector matches; 13 unmatched at direct indices 18–30; one startup
reference-order reversal. From index 31, all 3,827 samples match contiguously.
All 3,582 transport-stable samples match contiguously. Maximum voltage error
0.000237881 microvolts. Raw CQ matches on all 3,845 matched samples.

This validates decoder values, electrode mapping, voltage conversion and raw CQ
against Cortex for this headset/configuration and matched interval. It does not
validate physiological interpretation, CQ class calibration, other firmware,
or production transport reliability. Startup anomalies remain explicitly saved.
19 regression tests pass. Comparison: reference-paired/comparison.json;
reproduction: compare_paired.py; snapshot provenance: reference-paired/provenance.json.


### Stable consumer boundary — 2026-09-15

`Pipeline(output, sample_sink=callback)` preserves the complete raw/decoded
recording and only calls the consumer for samples marked transport_stable.
Delivered samples include `epoch`, `stream_index`, and `stable_segment`.
A new stable_segment starts after each recovery/reconnect; consumers must not
concatenate across these boundaries. Delivery uses a deep copy to protect the
recorded sample structure from consumer mutation. This is a synchronous hook;
consumers must avoid blocking the Bluetooth event loop.

The real paired-capture regression replays two epochs: all 7,716 decoded
samples remain in the recording, 7,164 stable samples reach the consumer, and
the startup discontinuities remain visible. This tests gating using real saved
packets; it is not a new physiological or live dual-reader validation.

### Acquisition hardening and live reliability — 2026-09-15

Production remains NOT RELEASED. Explicit acceptance list: PRODUCTION_READINESS.md.
Three 15-second reconnect cycles each reached stable status in ~2 seconds:
5,868 samples total; 6 rejected packets and 6 discontinuities all during startup.
Three-minute run: 23,104 samples, zero decode errors, two startup discontinuities,
22,788 stable samples; no issues after first stable status (soak-validation.json).
Fresh hardened 30-second run: 3,900 samples, 3,576 stable; two rejected frames
and two startup discontinuities, no connection interruptions or fatal errors.

Changes: stable-only consumer callback with segment boundaries; missing supported
configuration blocks calibrated consumer delivery; >0.5-second arrival gap resets
stability; fatal storage/consumer/notification errors stop acquisition; private
0600 recordings; per-explicit-device advisory lease; Ctrl-C shutdown record;
macOS dependency pins and RUNBOOK.md. 25 regression tests pass.

Cortex CQ.AF3 changes 4 -> 2 -> 1 -> 4 in the reference while raw CQ is ~5470.
This evidence does not support a simple independently validated raw threshold
mapping. CQ quality classes remain unknown in our implementation. No physiology
or brain-intent validation claim is made.


### Further release hardening — 2026-09-15

29 tests pass, including a subprocess SIGTERM test with a fake Bluetooth transport.
Readiness now expires during silence (0.5 seconds), not merely on next arrival.
Fatal notification callback errors stop acquisition without Bluetooth retry.
Added default 512 MiB explicit capture budget, summary fsync, and SIGTERM cleanup.
Dependency check passes. These latest changes are regression-tested; a new live
standalone qualification remains pending.

M4 EPOC X is still connected through Cortex. Root service com.emotiv.cortexv2
cannot be stopped by this SSH user without a password (sudo -n failed). Asked
user to disconnect headset in EMOTIV Launcher while leaving it switched on.
Do not infer standalone validation from a second reader sharing that connection.


### Fresh two-minute Cortex retest — 2026-09-15

Hardened stream captured 15,374 samples in 120 seconds alongside Cortex on M4.
Recovered reference through authenticated Parquet read: 391,680 rows; copied
footer unchanged before/after copying data; remote/local snapshot SHA verified.
15,361 unique matches requiring counter + all 14 ADC electrode values.
All 15,108 transport-stable samples match contiguously. No post-stability issues.
Maximum voltage difference 0.000237881 microvolts; all 15,361 matched raw CQ values
agree. Thirteen unmatched samples and one reference-order reversal are at startup;
two packets were structurally rejected and two counter discontinuities retained.
No ambiguous matches. capture_clean remains false; production remains unreleased.
See reference-retest/comparison.json and validation-provenance.json.

