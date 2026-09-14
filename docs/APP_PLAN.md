# Native EEG application plan

The application is native SwiftUI with shared Swift acquisition and file code for macOS, iOS and visionOS. Python remains a scientific reference and offline research tool; the native app must not call Python or Cortex to acquire EEG. No browser application is a second UI path.

## Ownership and acceptance

| Workstream | Scope | Acceptance |
|---|---|---|
| Native core | Port observed EPOC X BLE decoder, preserve ADC/units/provenance | Same fixture vectors as Python, framing and unsupported-config tests |
| Native acquisition | CoreBluetooth discovery, metadata, notifications, stop/disconnect | Physical headset test on each supported Apple platform; preserve raw notifications |
| Recording | Private append-only files, complete/incomplete distinction, export | Round-trip samples and failures tested; no account or artificial duration quota |
| Native workspace | Device selection, live waveform, channel readouts, recording library, export | Working UI using actual data only; replay explicitly labeled |
| Signal science | Spectra and bands, contact quality, artifacts, calibrated commands | Each estimator separately validated; never label descriptive EEG as intent/emotion |
| Runtime qualification | Startup, queue failures, long run and hardware interruptions | Recorded evidence and stated thresholds; no blanket production claim |
| Distribution | Signed Apple apps, privacy declarations, device testing | macOS/iOS/visionOS build + physical device verification; signing requires appropriate developer team |
| BCI/HID | Validated discrete commands through supported Apple accessibility integration | Explicit command calibration and confirmation; no EEG-to-action bypass |

## Product scope

Match useful outcomes of installed vendor apps with independent implementations: discovery/setup, live raw channels, raw contact values, sessions, event annotations, replay, scientific export and analysis. Vendor cognitive metrics, facial/mental commands, firmware updates and universal headset support are separate capabilities, not implied by an EEG decoder. Hardware firmware/config writes are outside this first native implementation.

The user requested unlimited raw EEG: there is no subscription or software time quota. Disk capacity, battery and OS Bluetooth/background limits remain visible constraints. Native release status remains pre-release until hardware qualification, persistence and distribution gates pass.
