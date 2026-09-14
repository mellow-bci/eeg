# Current state — 2026-09-15

## Verified

- Direct BLE acquisition from the physical EPOC X, using the same Python decoder for live and replay packets.
- Five-byte serial metadata and software revision **0740**; firmware characteristic was observed as **0730**. These are different metadata fields. The decoder gates on the software revision bytes, despite historical notes loosely saying “firmware 0740.”
- Exact read-only configuration **018000102010**, 14 channels, observed 128 samples/second.
- AES-256-ECB/XOR decode, electrode word mapping and ADC/7.8 conversion agree with unmodified Cortex output on identical stable samples in two simultaneous captures.
- Raw contact-quality word agrees with Cortex on all matched samples.
- Local TEST24 recording recovery passed authenticated Parquet decryption; deliberately corrupting a copy failed decryption.
- Three deliberate reconnect cycles recovered; a three-minute live run had no post-stability issues.
- Failure tests cover missing configuration, corrupt packets, silent input, consumer/storage failures, duplicate reader lease and SIGTERM.

## Not verified / not implemented

- Production release; a short soak is not sufficient production acceptance.
- General firmware compatibility, other hardware models or all operating systems.
- Accurate contact quality classes 0–4 derived from our raw CQ stream.
- EEG artifact removal, physiological source isolation, thought/speech/intent decoding, clinical validity.
- EMOTIV internal 2048 Hz ADC access. Actual exported stream is observed at 128 Hz.
- Calibrated IMU/motion output; auxiliary bytes are retained raw.
- Apple BCI HID emission, CAST/Anika actions or an autonomous command policy.
- Cryptographic integrity of BLE payloads; ECB is not authenticated encryption.

## Concrete remaining limitation

Cortex-connected startup delivers a brief out-of-order/invalid sequence. Whole structurally invalid notifications are rejected; valid but discontinuous samples are retained. The stability gate excludes startup anomalies. The source of that startup buffering is not conclusively attributed to headset, host BLE stack or Cortex. Do not call it fixed merely because downstream delivery is gated.

The test host used for comparison had Cortex connected. Earlier direct captures on another Mac worked, but an explicit repeatable standalone lifecycle qualification remains open.

## Native and calibration checkpoint

Native SwiftUI source builds on macOS and iOS/visionOS simulators. Its Swift decoder matches real archived raw notifications; the app imported and displayed an actual capture. Native physical-headset qualification remains open. See [NATIVE_APP.md](NATIVE_APP.md).

A prospective audio-cued eyes experiment captured27,880 samples; all12 trimmed windows were transport-usable, but posterior alpha behavior was mixed and the participant reported missed/uncertain cues. This run is excluded from model training and accuracy evaluation. Evidence: [session report](../evidence/experiments/20260915-eyes-session1/README.md). Cognitive scores, mental commands and Apple HID output remain unvalidated/disabled.

## Independent processing checkpoint

The canonical adapter/window/feature/profile workflow is implemented and software-tested. It uses independently specified spectral features, feature selection, PCA and diagonal Gaussian scoring with neutral/rejection and continuity resets. Profile hashes include recording provenance; evaluation refuses reused sessions/content. Proposals never enable system control. No real mental-command training/evaluation has been completed. The uncertain eyes run is suitable for input-path replay checks only. See [MENTAL_WORKFLOW.md](MENTAL_WORKFLOW.md) and [capability inventory](../capability-matrix.json).
