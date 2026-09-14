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
| Recordings | Local inventory with finalized/incomplete/corrupt distinction; bounded 1,280-sample pages; ADC CSV export; real raw capture JSON import through the native decoder | Search/tags, EDF/BDF export, automatic recording segmentation, very large library performance |
| Analysis | Real recorded waveforms and CSV for reproducible analysis | Native spectrum, artifact and band-power tools are visibly marked as future work |
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

CoreBluetooth callbacks and recording writes currently serialize on the main queue. Raw/sample memory is bounded, but a slow disk or expensive library/import operation can delay UI/notification processing. Move I/O behind a bounded serial delivery mechanism with explicit overflow and loss accounting before a production claim. Long-run rotation, storage-budget management, recoverable interruption, signed distribution, accessibility QA and physical mobile-platform background behavior remain release gates. App inventory/review can scan long files and is not yet indexed.

Raw decoding does not establish valid scalp contact, classify cognitive state or implement Apple's BCI HID input report path. Those capabilities require separate implementation and validation.

## Final reader consistency review

Inventory, paged replay and CSV export now share the same native-v1 schema, sample-shape, summary-count and failed-import validation. Replay validates the entire file snapshot even after filling its bounded page, so corruption after that page cannot be concealed. A structurally valid unfinished recording remains reviewable but is explicitly incomplete. Failed CSV exports are removed. Export is blocked while a headset connection exists, to avoid a synchronous full-file export competing with acquisition. Full-file reading is still main-queue work and requires background I/O/indexing qualification before large-library production use. No native live hardware capture was performed in this review.
