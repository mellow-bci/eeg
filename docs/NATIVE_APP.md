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
