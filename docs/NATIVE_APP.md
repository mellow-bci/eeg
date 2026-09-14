# Native EEG application

Status: **functional research preview, not a production-qualified or medical device application**. The application runs its decoder and recording code natively. Python, Cortex, an Emotiv login and a web server are not required by the native application.

## Components and one acquisition path

- `apple/Sources/EEGApp/AcquisitionModel.swift`: user-triggered CoreBluetooth discovery, connection, metadata reads, notification handling, local recording/review/export and bounded waveform preview.
- `apple/Sources/EEGCore/Decoder.swift`: CommonCrypto AES-ECB and CryptoKit SHA-256, exact observed 0740 framing and channel mapping; unknown metadata fails closed.
- `apple/Sources/EEGCore/RecordingStore.swift`: private append-only local JSONL, metadata/raw notification/sample/event records, finalized inventory, paginated sample replay and CSV export.
- `apple/Sources/EEGApp/EEGApp.swift`: shared SwiftUI navigation and adaptive native presentation on macOS, iOS and visionOS.

Live notifications and imported raw BLE captures both pass through `EEGDecoder`. The archival Python stack remains a scientific reference and qualification tool; it is not invoked by the native application.

## Available workflows

| Workspace | Working behavior | Explicit remaining scope |
|---|---|---|
| Live signals | User-initiated discovery; select/connect headset; raw ADC waveforms; count/rejection metrics; transport stability; private recording; text event markers; raw per-channel contact observations | Physical native-app acquisition qualification; validated good/poor-contact classes; motion decoding |
| Recordings | Local inventory with finalized/incomplete/corrupt distinction; bounded 1,280-sample pages; ADC CSV export; real raw capture JSON import through the native decoder | Tags, EDF/BDF export, automatic recording segmentation, very large library performance |
| Analysis | Real recorded waveforms, spectral density and band powers for reproducible analysis | Native spectrum and band powers are implemented; physiological interpretation remains unvalidated |
| Calibration | Clear explanation of independent command-calibration requirements | Native intent training and command outputs are not enabled |
| System | Storage path, local-only processing, release status and last 50 events | Signed distribution, physical iOS/visionOS qualification and stress qualification |

CSV preserves channel ADC values. It is not a complete replacement for JSONL: raw encrypted notifications, metadata, contact words and annotations remain in the original JSONL. Original raw capture import expects the repository capture schema (`info` plus `packets`) and caps the input JSON object at 64 MiB. This bounded import is separate from live recording duration; it does not impose a recording time quota. No synthetic signal is displayed.

## Build and launch

Requires a macOS development host, Xcode with the corresponding SDKs, and XcodeGen. Tested on Xcode 26.6 with the macOS/iOS/visionOS 26.5 SDKs. Deployment targets are macOS 14, iOS 17 and visionOS 1.

```sh
cd apple
swift test
./build-native.sh all
open ../build/native/macOS/Build/Products/Debug/EEG.app
```

`project.yml` generates the checked-in Xcode project and per-platform Info.plists. Regenerate after changing build configuration. Build individual platforms with `macos`, `ios` or `visionos` instead of `all`.

- macOS output: `build/native/macOS/Build/Products/Debug/EEG.app` (ad-hoc development signing).
- iOS Simulator output: `build/native/iOS/Build/Products/Debug-iphonesimulator/EEG.app`.
- visionOS Simulator output: `build/native/visionOS/Build/Products/Debug-xrsimulator/EEG.app`.

Simulator compilation does **not** establish Bluetooth hardware operation. For physical iPhone/iPad/Vision Pro, open `apple/EEG.xcodeproj`, select the platform target and a developer signing team, then test on the actual device. App Store/notarized distribution is not configured. No signing secrets are stored in this repository.

## User operation

1. Open EEG. It does not scan, connect or record automatically.
2. Choose **Find headset**, grant the platform Bluetooth permission, select the headset and connect.
3. Inspect transport and waveform state. Transport stability is continuity, not physiological quality.
4. Start recording explicitly. Add markers as needed. Stop recording before disconnecting.
5. In Recordings choose Review, page through actual samples, or export CSV. macOS uses the save panel; iOS/visionOS expose a system **Share exported CSV** link after successful export.
6. To inspect an existing raw BLE capture without connecting hardware, choose **Import raw capture** and select a real capture JSON. The resulting native recording retains raw packets and rejected-packet events.

All recording files are stored under the platform application-support `EEG/Recordings` directory. iOS/visionOS sandbox access is through the app and export sheet. There is no account requirement, subscription gate, cloud synchronization or software recording-duration quota in this implementation. Recording is still constrained by battery, storage and foreground platform execution.

## Acquisition failure semantics

- Connection, metadata and notification-start deadlines are respectively 15, 10 and 8 seconds. A timeout disconnects and surfaces a message; it never silently waits forever.
- Raw notification bytes are persisted before attempting decoding while recording.
- Every transport-stability transition is persisted as `transport_status` with `receivedAt`, reason and calibration availability. Starting a recording writes its current transport state. These events precede affected samples in file order, allowing eligibility to be reconstructed; they are not physiological-quality labels. Raw-capture imports use the same transition thresholds.
- A decoder rejection increments the error count, persists a `decode_error` event and resets transport stabilization. The capture continues, preserving expected startup anomalies for analysis.
- A storage error stops recording explicitly. The app attempts a checkpoint and finish independently so a failed checkpoint does not leave the writer open. A final summary may be unavailable when storage itself fails.
- At least 256 counted contiguous samples and two seconds are required for transport stability. Rejected packets and counter/arrival gaps reset it. A 0.5-second silence revokes stability; five seconds without notifications disconnects for explicit user retry.
- Orderly macOS application termination finalizes and disconnects. iOS/visionOS entering the background finalizes and disconnects: this is a foreground capture application, not a claimed background BLE recorder. Force-quit, crash or power loss can leave an incomplete file.
- The latest 1,280 preview samples are retained and waveform publication is throttled to approximately 10 Hz. No user-intent action is generated.

## Verified in this development pass

- Native decoder replay parity: 1,588 original samples (including 396 auxiliary-bearing notifications), 3,858 configured paired samples and all 15,374 latest Cortex-retest samples. Startup rejections and counter discontinuities match the archive; channel values and observed voltage conversion match Python.
- Swift package compilation and automated decoder/storage tests.
- Actual successful Xcode builds for macOS, iOS Simulator and visionOS Simulator.
- macOS app launched and its actual window visually inspected. A real `ble-capture.json` was opened through the app: 794 original notifications became 1,588 recorded samples with a finalized summary, and real waveforms rendered. No headset scan or live recording was initiated during UI inspection.

## Production qualification still required

This is an integrated native foundation, not feature parity with every Emotiv application. Physical-device discovery/start/stop/reconnect, sleep/wake, battery loss, independent acquisition without Cortex, sustained throughput and full-session durability have not been requalified in the native app.

CoreBluetooth callbacks and recording writes currently serialize on the main queue. Raw/sample memory is bounded, but a slow disk during live recording can delay UI/notification processing. Move live recording I/O behind a bounded serial delivery mechanism with explicit overflow and loss accounting before a production claim. Long-run rotation, storage-budget management, recoverable interruption, signed distribution, accessibility QA and physical mobile-platform background behavior remain release gates. App inventory/review can scan long files and is not yet indexed.

Raw decoding does not establish valid scalp contact, classify cognitive state or implement Apple's BCI HID input report path. Those capabilities require separate implementation and validation.

## Final reader consistency review

Inventory, paged replay and CSV export now share the same native-v1 schema, sample-shape, summary-count and failed-import validation. Replay validates the entire file snapshot even after filling its bounded page, so corruption after that page cannot be concealed. A structurally valid unfinished recording remains reviewable but is explicitly incomplete. Failed CSV exports are removed. Export is blocked while a headset connection exists, to avoid a synchronous full-file export competing with acquisition. Inventory, replay, import and export now run on a serial background file queue with main-thread result publication. Large-library indexing and stress qualification remain outstanding. No native live hardware capture was performed in this review.


## Interactive analysis and native chart references

The current UI implementation uses Swift Charts for spectral density and band powers, including frequency selection and explicit scientific units. A single LineMark path renders the 129-bin spectrum on all supported targets; this also builds against the CI SDK, which does not expose LinePlot. Scientific waveform rendering must preserve gaps and distinguish ADC values from calibrated voltage. A visually plausible trace is not evidence of valid contact or mental-command decoding.

Official design/implementation references reviewed:

- [Swift Charts](https://developer.apple.com/documentation/charts)
- [Creating a data visualization dashboard](https://developer.apple.com/documentation/charts/creating-a-data-visualization-dashboard-with-swift-charts)
- [Visualizing your app’s data](https://developer.apple.com/documentation/charts/visualizing-your-app-s-data)
- [WWDC23: selection and scrolling](https://developer.apple.com/videos/play/wwdc2023/10037/): selection bindings, rule marks, annotation overflow handling, visible domains and scroll position.

`Spectrum.swift` analyzes exactly 256 continuous calibrated samples at 128 Hz, using linear detrending, a periodic Hann window, one-sided density normalization and half-open frequency bands. Native fixtures compare every PSD bin and integrated band against the Python reference for a real recording window and a labeled synthetic 10 Hz test vector. The synthetic vector is a numerical test fixture, never a live source or product measurement. Live analysis requires stabilized transport; replay currently exposes its transport provenance as unverified. No artifact threshold result establishes physiological readiness.

`ProcessingSettingsView` edits the canonical `eeg.processing-settings.v1` contract and persists it atomically. It supports import/export for the existing offline training workflow; native training is not implied by the presence of settings.


### Native chart checkpoint, 2026-09-15

All 21 Swift tests passed and macOS, iOS Simulator and visionOS Simulator builds succeeded. Actual macOS UI review imported the configured archived paired capture (1,929 raw notifications, 3,858 decoded samples, zero rejections), selected its recording and opened Spectrum. The real O1 window ending at sample 1,279 rendered a labeled PSD chart and reported 7.96 µV detrended RMS and 45.22 µV peak-to-peak. These rounded UI measurements describe that archived window only. No live capture, cognitive score or hardware qualification was performed in this checkpoint. Complete interactive, accessibility and mobile visual QA remain outstanding.

### Interval review and waveform readability (2026-09-15)

Recording review connects `WaveformWorkbench`'s exact original sample selection to
`IntervalAnalysisView`. Selecting or navigating a recording page resets frozen
inspection through source identity. Display centering, amplitude limits and channel
height never modify stored measurements or the samples sent to analysis.

Channel lanes default to 56 points, with 29-point compact and 88-point expanded
choices. The optional selected-channel inspector is 240 points tall. Common
amplitude controls retain explicit ADC/µV units; µV requires calibration metadata.
Fixed-scale clipping is disclosed. These changes improve inspection space; visual
patterns alone do not establish a mental-command trigger.

Interval analysis uses the canonical spectrum implementation: complete 256-sample
windows with a 128-sample hop. Structurally invalid windows are rejected and remain
blank in the spectrogram. The average uses only structurally accepted windows;
artifact flags and uncovered trailing sample counts remain visible. Spectrogram
horizontal coordinates are window ordinals, explicitly distinct from measured
receipt timestamps. No gaps are interpolated and no physiological interpretation
is inferred. Five interval tests cover the single-window reference, overlapping
window count/tail, structural gaps, flagged flat signals and all-rejected input.

Verification: integrated `swift test --package-path apple` passed 26 tests with
zero failures. Interactive accessibility and hardware qualification remain separate
from these automated results.

### Native mental-feature bridge

`EEGMentalFeatures.extract` computes all 70 channel-major log-band powers using
`EEGSpectrum`; no second spectral implementation was introduced. Channel order,
half-open bands, log floor and feature configuration identity match
`processing/features.py`. Missing calibration on any electrode rejects the entire
vector. Artifact flags use the reference's stable aggregate ordering.

Reproduce the real-recording numerical oracle with
`python -m tools.generate_native_mental_fixture` in the research environment, then
run `swift test --package-path apple`. All 70 values match the Python/SciPy oracle
within 1e-7 log-power units. The integrated suite now passes 28 tests. This is one
recorded numerical fixture, not cross-session mental-command validation. The
native profile trainer/classifier, transport/epoch readiness integration and
prospective command/neutral evaluation remain unfinished. A usable feature vector
alone never authorizes a command or system action.

### Native classifier numerical kernel

`EEGMentalScoring` now performs feature normalization/selection, PCA projection,
equal-prior diagonal Gaussian log likelihoods, stable softmax and trained-distance
comparison. It validates parameter shapes, finite values and positive scales/variances,
and rejects numerical overflow. Six manufactured feature cases match the independent
Python reference's class scores within 1e-10. Regenerate the oracle with
`python -m tools.generate_native_scoring_fixture`.

This kernel deliberately is not a profile loader, training UI or command detector.
Profile integrity/provenance, configuration matching, valid-window delivery,
persistence/rejection policy and session-separated evaluation must be integrated
before exposing native inference previews. It emits no command or system action.
The current local Swift suite passes 30 tests; physiological validity is untested.

### Native experimental detector state

`EEGExperimentalDetector` wraps the scoring kernel with feature configuration,
participant/session/window identity, continuity, timing, artifact and numerical
rejection. It applies configured score/margin thresholds and consecutive-window
persistence, retaining the first evidence timestamp. Rejection or a session,
continuity or timing gap resets pending evidence. Counts saturate at the configured
persistence threshold. Every result remains `no_reliable_command`, with a nil command
and disabled system control, including when an experimental candidate is present.

Four state-test groups cover persistent candidates, gap/session/segment boundaries,
invalid windows, neutral/outliers and overflow. The local suite passes 34 tests.
These use the manufactured scoring fixture, not physiological acceptance data.
Native profile integrity/provenance loading and the full training/evaluation UI are
still pending. The detector is a sequential value type: its caller must serialize
inference and must supply windows produced by the validated canonical adapter.

### Native profile loading and inspection

Calibration now includes an Open profile action for the existing
`eeg.mental-profile.v2` format. Loading reads a bounded local file off the main
thread, verifies integrity and supported design/provenance, and displays participant,
classes, training-session count, profile identity and persistence. It keeps the
opened profile in memory only and does not change acquisition or start inference.

`ProfileCanonicalJSON` retains Python-generated numeric/string token spellings while
sorting object keys and removing formatting whitespace, so hashing does not round
floating-point values through Foundation. It rejects duplicate keys and bounds file
size (8 MiB) and nesting (64). It is intentionally not a universal JSON canonicalizer:
re-encoding equivalent values with different number/escape spellings can fail integrity.
Checksums are not signatures and do not verify labels or recording provenance truth.

Tests load the Python synthetic fixture, vary whitespace, detect tampering/duplicate
keys and reject recomputed-checksum files with unsupported design, missing settings,
invalid provenance or zero scales. Local Swift suite: 37 tests passed. macOS, iOS and
visionOS builds passed after adding the inspection UI. Interactive profile-import
accessibility, native training, replay inference and physiological validation remain.

### Native recording-aware analysis windows

`EEGRecordingStore.analysisWindows` shares replay's bounded line reader and schema
validation, and requires a final sample-count summary. Its callback is provisional:
consumers must discard all results if reading fails, including a missing summary.
This is an offline core API; it is not yet wired into the inference UI.

The assembler emits nonoverlapping 256-sample windows, rejecting partial tails,
missing/unsupported device configuration, unstable transport, recovery boundaries,
sample discontinuities, counter/index gaps (including between windows), timing gaps,
unobserved 128 Hz rate, invalid ADC word mapping and inconsistent calibration.
Original samples remain unchanged. Valid here means structurally eligible;
spectral artifact checks and detector rejection still apply. Metadata and a completed
file do not establish physiological validity or authenticate the source.

The recording path check compares standardized file paths, accepting equivalent
Foundation directory URLs with or without a trailing slash while rejecting paths
outside the store. Native tests cover completed/unfinished files, missing metadata,
recovery and cross-window gaps. No live hardware qualification was performed for
this change. Standalone local EEG parity remains the priority; Cast is unchanged.

### Offline profile replay diagnostics

Calibration's loaded-profile panel now offers an offline inference check over a
completed local recording. It uses `analysisWindows` → `EEGMentalFeatures` →
`EEGExperimentalDetector`, retaining all window rejection reasons. Analysis runs
away from the main thread. A configurable positive window limit (initially 10,000)
causes explicit failure on exhaustion; no partial report is published. The UI shows
the first 100 rows and complete report counts. It does not alter acquisition.

The report includes the SHA-256 of the exact bytes consumed by the recording reader,
profile identity and user-asserted participant/session identity. Training session IDs
and canonical EEG fingerprints are rejected, even after renaming or reserializing.
The fingerprint matches the Python trainer: ordered counter and fourteen-channel ADC
values, with metadata, timestamps and file encoding excluded. The separate byte hash
identifies the source file representation. Neither fingerprint detects arbitrary
shared excerpts or altered counters. Source identity assertions remain unverified. The reader works
from a file-length snapshot; the digest identifies consumed bytes, not an authenticated
immutable file. Do not edit recordings during analysis.

This is an unlabeled diagnostic, not a physiological accuracy evaluation. It emits
no actionable command, and does not calculate precision/recall from predictions.
Native labeled training, cross-format provenance matching, report export, cancellation,
and interactive accessibility/performance qualification remain outstanding. Tests use
synthetic recordings and synthetic profiles; they establish rejection paths and
plumbing, not successful intent decoding.


### Replay provenance correction

Inspection of `processing.workflow.recording_fingerprint` found that native replay's
initial check used a file-byte hash against the trainer's canonical measurement hash.
That initial check did not protect ordinary Python-trained profiles from content reuse.
`EEGRecordingFingerprint` now implements the same bounded integer-ADC JSON spelling
and chronological counter/channel sequence as Python. A fixed Python SHA-256 oracle
checks the complete 512-sample synthetic recording; timestamp/serialization changes
leave its content identity unchanged. A profile carrying that canonical digest is
rejected under a different session name. This is a correctness fix, not new evidence
of mental-command accuracy.

### Native training preparation

`EEGTrainingData.prepare` accepts explicitly usable, accepted and label-verified
70-feature records for one participant. It requires unique window identities,
one canonical recording fingerprint per session, distinct content across at least
two sessions, neutral plus a task class, and at least 20 windows spanning two
sessions for each class. The optional processing-settings training budget is
honored with an error rather than truncation. These are eligibility rules, not
evidence that labels are true or sessions physiologically independent.

It fits population mean/standard deviation on supplied training data only, replaces
standard deviations below 1e-8 with one, ranks features by equal-class between/within
variance ratio with a 1e-6 denominator regularizer, uses original feature order to
break ties, and prepares centered selected columns for PCA. This implements the
existing independent Python recipe; no parameters are claimed to come from Cortex.
Nonfinite intermediate results are rejected. Original records remain immutable.

Reproduce the manufactured Python oracle with:

```sh
/tmp/chorus-epoc-ble-env/bin/python tools/generate_native_training_fixture.py
swift test --package-path apple
```

The environment path is the local validation environment; the generator needs Python,
NumPy and the repository's test fixture module. The committed fixture contains 80
synthetic records and expected normalization/selection/PCA input values. Native values
match within 1e-10 in the current test run. It contains no physiological data. This
core API does not yet perform SVD, fit Gaussians, save a profile, or expose native
training controls. Recording-based label collection must establish input provenance;
decoding a feature JSON alone does not do so.
