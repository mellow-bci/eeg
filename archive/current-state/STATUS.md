# EPOC X direct BLE acquisition

## CURRENT: decoding breakthrough, 2026-09-14

This section supersedes the historical unresolved decoder notes below.

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

### Same-sample comparison preparation — 2026-09-15

M4 system Bluetooth inventory confirms EPOCX connected while Cortex runs.
Prepared isolated /tmp/chorus-epoc-validation-env on M4 with bleak 1.1.1,
pycryptodome 3.23.0 and PyObjC 11.1. Connected-peripheral probe fails with
“BLE is not authorized - check macOS privacy settings”. No simultaneous
packets acquired; no comparison performed. Bluetooth privacy authorization
on M4 is required before testing a second local reader. No Cortex changes.

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

### Labeled CQ replay and reference importer — 2026-09-14

- Traced CQ list initialization and labeled all 14 rotating slots by electrode.
  Saved separate blinks-contact-quality-labeled.jsonl; raw capture untouched.
- Quality classes remain unset: calibration/upstream transformation and
  independent reference still unverified.
- Added documented V2 reference CSV validation, provenance hash, interpolation
  and gap reporting. 19 tests pass; synthetic CSV tests are format tests only.
- Opened installed official EmotivPRO on M4. No reference recording imported;
  awaiting login/export readiness. See CONTACT_QUALITY.md for exact limits.

### Contact quality investigation — 2026-09-14

- Added offline raw CQ extraction for exact observed configuration; live
  decoder/transport unchanged. Full evidence and limits: CONTACT_QUALITY.md.
- Replayed blink capture: 3,794 updates, 271 per each of 14 rotating slots.
- 17 regression tests pass. Named electrodes and quality classes remain null
  pending complete normalization/mapping and independent reference validation.
- Official EEG/CQ export route verified in vendor API documentation. Awaiting
  whether M4 EMOTIVPRO is signed in and can record/export a reference.

### Audible blink test — 2026-09-14 18:58 UTC

- Known-ID attempt failed before cues; discovery retry completed six blink
  trials and rest through the same acquisition/cue runner (--protocol blinks).
- Source: live-blinks-discovery-20260914T185827Z.jsonl. 17,300 samples,
  ~128.077 Hz, zero decode errors, gaps or interruptions; capture_clean=true.
- analyze_blinks.py compares equal 4-second windows before/after software
  cue onset, linear detrend only. All 12 windows contiguous and stable.
- AF4 post/pre RMS ratios: 4.41, 5.22, 4.59, 6.24, 5.46, 4.33.
  AF3: 2.68, 1.24, 3.60, 18.05, 3.06, 3.37.
  Posterior O1/O2 ratios range 1.42–2.31, smaller than AF4 each trial.
- Repeatable frontal response associated with blink cues supports signal
  responsiveness and is consistent with ocular artifacts. Actual blink
  timing/count not measured; no silent/sham cue control. Does not establish
  isolated neural EEG, exact channel mapping/scaling, or intent decoding.
- Raw capture, software speech-onset/completion markers and descriptive
  .blink-analysis.json retained. Physiology validation flag remains false.

### Audible eye-cue capture — 2026-09-14 18:47 UTC

- User confirmed the Mac speech check was audible. audible_eye_test.py ran
  five spoken phases through the existing Pipeline/live acquisition path.
- Discovery-first attempt failed safely before eye closure; known-ID retry
  completed all phases. Source: live-audible-direct-20260914T184711Z.jsonl.
- 19,340 samples over 150.959 seconds of arrivals (~128.101 Hz), 19,080
  transport-stable samples, zero decode errors, counter gaps or interruptions.
  capture_clean=true. All five analyzed phase segments contiguous and stable.
- O1 8–13 Hz power (uV²), open/closed/open/closed/open:
  11.274 / 8.925 / 9.995 / 7.743 / 13.829.
  O2: 14.846 / 14.743 / 22.017 / 11.549 / 27.357.
- No repeatable closed-eye increase demonstrated. This is inconclusive for
  physiological validation; it neither proves physiological correctness nor
  identifies decoder failure. No intent/control inference enabled.
- Cue markers use local speech-process completion and acquisition monotonic
  clock. Actual eyelid state/compliance and acoustic latency are not measured.
- Next validation priority: verified contact-quality interpretation and an
  independent reference comparison, rather than treating transport success
  or repeated eye tests as proof. Analysis saved in .phase-analysis.json.

### Controlled eye-cue capture — 2026-09-14 18:37 UTC

- After user power-cycled headset, discovery connected. Captured 150 seconds:
  live-controlled-20260914T183707Z.jsonl; 19,216 samples, zero decode errors,
  zero counter gaps, 18,956 transport-stable samples. capture_clean=true.
- Text cues eyes-open / closed / open recorded in sidecar markers JSONL.
  Cue compliance is NOT sensor-verified (particularly eyes-closed text cues).
- compare_eye_phases.py compared central ~20 seconds per phase, trimming
  transitions. All three analyzed segments have contiguous stable counters.
- O1 8–13 Hz powers: 14.317 / 10.454 / 9.405 uV²; O2: 26.441 / 15.060 /
  21.593 uV² (open1 / closed / open2). Relative fractions slightly increased
  closed, but absolute power did not consistently increase. Inconclusive;
  not independent physiological validation, not evidence of decoder failure.
- Results saved in .phase-analysis.json. Next: verified contact-quality decode
  and a repeatable reference comparison; use audible/timed cues or participant
  confirmation for future eye-state tests. No inferred intent/actions enabled.

### Controlled-test attempt — 2026-09-14 18:35 UTC

- User confirms sensor pads prepared. Eyes-open/closed test could not start:
  two known-ID connection attempts and two discovery attempts found no headset.
- Files: live-eyes-test-20260914T183457Z.jsonl and
  live-eyes-discovery-20260914T183548Z.jsonl; both zero samples.
- M3 Bluetooth controller is on. Cause of headset unreachability is not known.
  User needs to check headset power/connection before repeating timed test.
- Earlier worn capture remains valid as recorded; no new physiological result.

### First worn capture — 2026-09-14 18:27 UTC

- User reports wearing headset. Discovery missed it; direct CoreBluetooth ID
  succeeded. live-worn-direct-20260914T182649Z.jsonl: 3,840 accepted samples,
  zero errors/gaps, 3,584 transport-stable samples, ~128.062 Hz.
- analyze_signal.py reports descriptive ADC rails/unchanged steps and Welch
  spectra on longest contiguous stable segment. Analysis dependencies are
  separate requirements-analysis.txt; raw acquisition dependencies unchanged.
- All 14 channels vary, no ADC rails reached. Substantial slow shifts present;
  no electrode-contact or physiological-success claim. Summary saved as
  worn-signal-summary-20260914T182649Z.json.
- Awaiting whether pads were prepared and reference sensors contact scalp.
  Timed controlled eyes-open/closed and artifact validation still outstanding.

### Current hardened acquisition — 2026-09-14 18:22 UTC

- User confirms NOT wearing headset. Transport acquisition only; no claim of
  physiological validation or intent decoding.
- Enabled separate uncentered vendor-scaled microvolts only for exact live-read
  configuration 018000102010; ADC counts remain unchanged and preserved.
- Added explicit transport recovery/stability state, per-epoch stable counts,
  clean-capture status, notification-silence watchdog and deliberate reconnect
  cycles. No relaxed validation, interpolation or concealed startup errors.
- Two-minute capture: 15,424 accepted samples; all errors/gaps in first ~0.1 s.
- Three deliberate reconnect cycles: 7,848 samples; each reached stable state.
- Final updated-code capture: live-final-20260914T181959Z.jsonl; 2614 accepted samples,
  2288 stable samples, 2 startup packet errors / 1 gap, no connection errors
  or silent-transport interruptions. Stream stable at end; capture not clean.
- Fourteen tests pass including recorded reconnect anomalies, conservative
  scaling behavior and a simulated silent-transport watchdog. See VALIDATION.md.
- Pending user/hardware-dependent checks: wear/contact/reference validation and
  unexpected radio-loss recovery. Existing automation stays paused. No CAST/HID
  actions, calibration or physiological success claims are enabled.

### Fresh live success — 2026-09-14 18:12 UTC

- User powered on charged headset. Direct BLE connection and decoding succeeded
  in one fresh 30-second run: live-charged-20260914T181205Z.jsonl.
- 1,920 original notifications, 3,840 EEG sample records, zero decoding errors,
  zero counter gaps, observed 128.054 Hz. Channels vary; these are not mock or
  replay samples. No auxiliary records in this run.
- Read-only configuration returned 018000102010. Configuration byte 3 is
  0x10 (16-bit EEG resolution), selecting the traced divisor 7.8. Raw ADC
  remains preserved; independent voltage/physiology validation still pending.
- Second capture live-reconnect-20260914T181253Z.jsonl reconnected and
  decoded 1,338 samples, but two startup packets failed counter validation
  and one gap was recorded in the initial burst. Original packets preserved.
  Reconnection is possible, but seamless recovery is NOT yet verified.
  Next: characterize startup buffered packets and counters without suppressing
  errors, then longer fresh acquisition. Physiological validation still pending.

### Heartbeat 17:01 UTC — configuration characteristic verified; hardware needed

- UUID initializer at 0x100f8d4b4 proves global 0x1033e5f10 is
  81072f44-9f3d-11e3-a9dc-0002a5d5c51b. Evidence config-uuid-init.txt;
  static scan helper find-config-xrefs.py and config-xrefs.txt retained.
- Vtable slot resolves to 0x100f82678, confirming captured payload is sent
  to the traced configuration parser. This closes the BLE configuration path.
- stream.py now reads that characteristic with a five-second bound before
  subscribing, preserving raw hex in stream metadata. Read failure is explicit
  and does not prevent ADC acquisition. No config writes or voltage guessing.
- Ten regression tests pass. Read addition has not been tested on hardware.
- Two live attempts in live-20260914T170134Z.jsonl still found no headset.
  Next meaningful validation requires headset powered on near M3 on battery:
  fresh decoded capture plus actual configuration bytes, followed by recovery
  and reference/worn-headset signal validation. Pausing unattended retries
  pending hardware availability rather than repeating unchanged scans.

### Heartbeat 16:29 UTC — BLE configuration routing

- `live-20260914T162934Z.jsonl`: two not_found attempts, zero packets.
- Traced onServiceDetailsDiscovered: at 0x100f8a0e4 it passes stored payload
  this+0x7e8, headset type and revision through vtable slot +0x98.
  Saved ble-details-complete.txt and ble-config-vtable.txt for verification.
- UUID comparator target 0x1033e5f10 is a dynamically initialized QString;
  static memory is zero, so reading it cannot resolve its text. Need its
  initializer/xrefs (do not repeat memory reads). Original payload comes from
  extractEmotivInfos 0x100f88fcc..0x100f89030.
- No decoder changes or fresh EEG validation. Next offline action: locate
  global QString initializer for 0x1033e5f10; then add verified read-only
  configuration metadata acquisition to the existing stream pipeline.

### Heartbeat 15:58 UTC — resolution field trace completed

- Live file `live-20260914T155804Z.jsonl`: two not_found attempts, zero packets.
- getInputDeviceInfo at 0x101242ec0 copies the struct at this+0x30;
  copy routine 0x10000cd34 preserves offsets +0x88..+0xa1. Thus device
  EEG-resolution field +0xc4 becomes returned info+0x94, then option+0xac,
  then correction+0xb4. This closes the bit-depth-to-divisor software trace.
- Saved `device-info-copy.txt` and `ble-config-read.txt`. Current recorded
  metadata contains only standard 2a19/24/25/26/27/28/29 values, not a
  configuration payload. Cannot establish this capture's voltage scale yet.
- Next targeted trace: extractEmotivInfos stores a QByteArray at this+0x7e8
  and characteristic at +0x818 (0x100f88fc0..0x100f89030); resolve compared
  QString constant and where that payload feeds setHeadsetConfigFromByteArray.
  This is static inspection only; do not execute vendor writes.

### Heartbeat 15:26 UTC — configuration trace narrowed

- Two bounded attempts in `live-20260914T152634Z.jsonl` found no headset;
  zero packets/samples. No fresh live validation.
- Saved read-only official binary traces `resolution-config.txt` and
  `processing-option-init.txt` in local-app-analysis.
- Confirmed correction field this+0xb4 is copied from DataProcessOption+0xac
  (copy routine 0x101059bac copies the 16-byte block at +0xa8 unchanged).
  createDataProcessingObject at 0x100fe925c copies InputDeviceInformation+0x90
  into option+0xa8, so the relevant source field is device-info+0x94.
- setHeadsetConfig's typed arguments establish AbstractInputDevice+0xc4 as
  EEG resolution; the byte-array parser writes configuration byte 3 there
  (0x101241920). Need finish getInputDeviceInfo copy trace to connect +0xc4
  to returned +0x94, and trace BLE configuration characteristic dispatch.
- Existing output remains unsigned ADC counts. No voltage assumption or
  device configuration writes. Next: inspect getInputDeviceInfo at 0x101242e94
  and BLE config reception; determine whether recorded metadata contains it.

### Heartbeat 14:20 UTC — electrode mapping completed in software

- Two live attempts in `live-20260914T142034Z.jsonl` returned not_found.
- Completed static electrode mapping using the vendor channel enum-name map,
  default EEG output QList initializer, makeEEG column stores and getRawEegId
  word indices. Full evidence chain and mapping are in PROTOCOL.md.
- IMPORTANT: display order differs from raw word order. AF3 is word 2, F3 is
  word 0. Decoder now emits `electrodes_adc` alongside unchanged raw words,
  with `mapping_basis: official_software_static_trace`.
- Replay `decoded-labeled-20260914T142034Z.jsonl` contains all 1588 labeled
  sample records, zero errors/gaps. Ten tests pass including fixed sample
  assertions for the nontrivial AF3/F3/FC5 mapping.
- Mapping is software-verified, not independent physiological validation.
  Remaining offline task: trace device bit-depth/configuration used by
  convertADCToMicrovolt (this+0xb4 compared with 0x10, divisors 7.8/1.95),
  then determine whether existing device metadata establishes that setting.
  Do not assign voltage units based only on plausible value ranges.

### Heartbeat 13:47 UTC

- Two attempts in `live-20260914T134734Z.jsonl` returned not_found. No fresh
  live samples. Existing decoder unchanged.
- Static ARM64 reference scan found channel-name map initialization at
  0x101fd47b8 (saved `channel-map-values.txt`, `channel-map-init.txt`). The map
  at 0x1034c0248 contains these verified enum/name pairs:
  40 AF3, 43 F7, 45 F3, 51 FC5, 54 T7, 64 P7, 69 O1, 77 O2, 82 P8,
  92 T8, 95 FC6, 101 F4, 103 F8, 106 AF4.
- This establishes enum names, NOT their mapping to ADC word offsets yet.
- `InputDevice::setDefaultChannels` at 0x100fe9620 saved in
  `default-channels.txt`; jump table `default-branch-table.txt` proves headset
  type 7 branches to 0x100fe9984. It passes global channel QLists at
  page (0x100fe9000 + 9224*4096), offsets 0x1a8, 0x1c0, 0x1d8, 0x208,
  into setChannels. Next: trace initialization of those QLists, then match
  list order to `EpocXDataOutput::makeEEG` / getRawEegId. Do not guess.

### Heartbeat 13:16 UTC

- Two discovery attempts in `live-20260914T131604Z.jsonl` returned not_found;
  no new hardware validation.
- Fixed sample identity across reconnections: `stream.py` now emits an explicit
  connection epoch on packets/samples and a monotonically increasing
  `stream_index`, while keeping each decoder's original per-epoch index.
  Summaries include per-epoch sample counts and arrival spans so outages can be
  distinguished from acquisition intervals.
- Ten tests pass, including replay-backed reconnection-boundary and output
  preservation tests. These verify software behavior only, not BLE recovery.
  Next offline task remains the channel-map initialization trace documented below.

### Heartbeat 12:44 UTC

- Two bounded discovery attempts in `live-20260914T124434Z.jsonl` returned
  not_found. No new live sample or physiological-validation claim.
- Cached full arm64 symbol inventory in `local-app-analysis/all-symbols.txt`
  to avoid repeatedly fetching it. Static channel-name lookup uses a runtime
  map, so names cannot be established merely from that function's disassembly.
- Saved `channel-names.txt`, `channel-data-info.txt`, `eeg-info.txt` for next
  mapping/scaling audit. `Core::channel2StringDb` (0x101fc6898) reads a runtime
  map; `Core::getChannelDataInfo` (0x101f2d1a0) dispatches EEG metadata to
  `Core::getEegInfo` (0x101f2cc90). These are targeted evidence, not a validated
  electrode mapping yet. Continue tracing map initialization/output ordering;
  leave existing raw ADC output unchanged until the mapping is established.

### Heartbeat 12:12 UTC

- Three bounded discovery attempts in `live-20260914T121233Z.jsonl` all returned
  not_found. No new live hardware samples obtained.
- Added duplicate-packet and deliberate body-corruption tests; all eight tests
  pass. The corruption test demonstrates that a modified ECB block away from
  record headers can alter ADC values while counters/types remain valid. This
  is a protocol-integrity limitation, NOT evidence that the saved data is wrong.
- Decoder now includes `integrity_verified: false` on every sample, alongside
  `physiology_validated: false`. Header/counter continuity strongly supports the
  correct key/framing, but must not be described as independent ADC validation.
- Next offline lead: trace electrode-name ordering from the official output
  schema. `EpocXDataOutput::makeEEG` is at 0x1010b81bc and already saved in
  `local-app-analysis/eeg-output.txt`; do not guess names from common EEG order.

- Implemented independent `decoder.py` for observed firmware 0740, using the
  version-4 path found by static analysis of the official M4 CortexService.
- `stream.py` is the single replay/live acquisition entry point. It writes
  original BLE packets, decoded samples, auxiliary records, errors and summaries
  to exclusive-create, flushed JSONL files. No vendor apps needed at runtime.
- `decoded-eeg.jsonl`: all 794 real notifications successfully decoded into
  **1,588 consecutive sample records; 14 raw EEG ADC values each; 396 auxiliary
  records; zero decode errors; zero counter gaps**. Observed rate 128.0455 Hz.
- Six meaningful tests in `test_decoder.py` pass: complete capture, known initial
  ADC fixture, wrong serial rejection, unsupported revision, truncation, gap.
- Values are unsigned raw ADC counts in wire order. Electrode labels, microvolt
  scaling and physiological validity are not claimed. See `PROTOCOL.md` for exact
  code addresses/evidence and remaining checks.
- Latest discovery `live-v4-attempt.json` and direct-ID attempt
  `live-decoded-attempt.jsonl` both report device not found. Live acquisition and
  decoding in one fresh run are NOT yet verified. No Cortex process on M3; M4
  has official apps running, but no evidence yet they hold this headset.

### Next unattended action

Run `/tmp/chorus-epoc-ble-env/bin/python artifacts/epoc-x/stream.py --seconds 30
--attempts 3 --output artifacts/epoc-x/live-<unique-timestamp>.jsonl` from the
workspace root. If device is absent, retain explicit status and continue useful
offline validation; do not repeat older AES-key guessing. Never label replay as
live or off-head readings as validated physiology. The next concrete success is
a fresh live decoded stream. Longer reconnection test and reference validation
follow. Do not modify firmware, activate DFU or emit user actions from raw EEG.

## Verified

- M3 connected directly to EPOCX (E50213EE) over Bluetooth.
- `ble-capture.json` contains 794 notifications captured without application commands.
- `transport-analysis.json`: 398 payloads of 64 bytes and 396 of 84 bytes, each around 32 notifications/second. Notification rate is not EEG sample rate.
- Device metadata reported firmware bytes `0730`, software bytes `0740`. Preserve these raw values rather than assuming a version interpretation.
- `capture.py` records metadata and notifications; `analyze.py` replays capture files to characterize framing. Neither emits EEG or intent events.

## Unresolved

- No validated decryption, channel mapping, scaling, sample counter or sample rate yet.
- Older CyKit AES key candidates did not produce a credible counter sequence in initial offline trials. This is not proof of the new cipher or key format.
- EMOTIV Cortex 4.6.0 release notes explicitly mention updated encryption for EPOC X firmware 740: https://emotiv.gitbook.io/cortex-api/release-notes . This is a relevant lead given metadata `0740`, not a confirmed identification of this device's encryption.
- Off-head captures establish transport only. Physiological EEG validation requires a separate worn-headset reference test after decoder validation.
- Apple BCI HID and CAST intent dispatch remain unimplemented; unknown packets must not trigger actions.

## Reproduce on M3

Use `/tmp/chorus-epoc-ble-env/bin/python capture.py --seconds 15 --output off-head.json` from this directory, then `python3 analyze.py off-head.json`.

The temporary environment uses Python 3.9, bleak 1.1.1 and PyObjC 11.1. Capture only subscribes to the observed proprietary notification service and reads its readable metadata plus standard battery/device information. No guessed start commands or DFU operations.

## Next validation gates

1. Recover and verify the device-specific framing and encryption against recorded packets.
2. Validate counters, channel mapping, scaling and sample timing against a trusted reference.
3. Verify worn-headset signal quality and controlled artifacts before training intent decoding.
4. Add calibrated explicit selection/confirmation events, then test CAST and Apple HID independently before connecting real actions.

## Unattended progress, 2026-09-14

- Fresh 20-second capture attempt ended at discovery: device not found. `unattended-capture.json` records the attempt; prior capture retained.
- Added `check_legacy_framing.py`, screening published older serial-based AES key layouts with raw, reversed and ASCII serial representations, first-block offsets and counter positions. Screened 15,360 hypotheses on the captured notifications. Best simple counter consistency was only 3.78%; no credible decoder identified. This limited screen does not rule out other packet framing or encryption.
- Verified the diagnostic detects a synthetic encrypted counter sequence with 100% consistency and still labels its output decoded=false. Synthetic fixture is not headset evidence.
- CyKit issue comments reinforce lack of validated EPOC X support: https://github.com/CymatiCorp/CyKit/issues/32 (maintainer lacked a headset); https://github.com/CymatiCorp/CyKit/issues/26 and https://github.com/CymatiCorp/CyKit/issues/39 report incorrect/unverified waveforms. Do not spend future runs repeating these searches.
- NeuroTechX list reviewed: Mushu's actual `libmushu/driver/emotiv.py` uses old USB 32-byte EPOC framing; BrainFlow supported-board docs do not list EMOTIV. LSL, PyBCI and MOABB are useful downstream, not verified fixes for current encryption.
- App heartbeat `epoc-x-direct-acquisition` created for this task, every 30 minutes. Continue protocol work and bounded discovery with unique capture filenames; pause when completion or a concrete user dependency is reached.

## M4 installed app breakthrough

- User identified Emotiv apps on M4. SSH `ssh -o BatchMode=yes m4` works with existing authentication. Desktop app inventory did not list Emotiv, but filesystem confirmed `/Applications/EmotivApps`.
- Installed Cortex component manifest filename reports 4.13.3.525.2. Main binary: `/Applications/EmotivApps/EMOTIV Launcher.app/Contents/MacOS/CortexService` (universal arm64/x86_64).
- Read-only strings/symbol inspection confirms exact observed BLE UUIDs and named EPOC X code, including `EpocXDataDecryption::decryptNewPack`, `generateAesKeyVersion2`, `aesKeyVersion2_EpocXMode`, `aesKeyVersion2_STDMode`, and `EpocXDataValueCorrection::convertADCToMicrovolt`.
- Evidence and binary hash saved in `local-app-analysis/cortex-symbols.json`; static LLDB disassembly saved in `key-routines.txt` and `packet-routines.txt`. No processes attached, app patched, or protection settings changed.
- Key routine checks QByteArray length >4 and uses first four serial bytes through a SIMD lookup table. Original metadata serial is five bytes e50213ee2b; earlier legacy diagnostic used four-byte advertised suffix. Need trace actual caller, mode, lookup constant and packet transformation before interpreting this routine as the capture's decoder.
- Continue with static targeted disassembly using installed M4 LLDB. This concrete implementation supersedes broad guessing. Do not confuse generic cloud/file encryption routines with headset processing.
