# Standalone EEG application: evidenced feature matrix

Checkpoint: 2026-09-15. This is a product backlog, not a claim of EMOTIV feature parity.
The application should use our direct hardware pipeline and locally owned recordings. No
vendor app patching, subscription unlocking, or vendor cloud service is needed for our
recording/export path. “Unlimited” means no software subscription cap; battery, storage,
Bluetooth bandwidth, supported hardware modes and retention limits remain real limits.

## Installed applications confirmed on M4

Read-only SSH inspection of `/Applications/EmotivApps` found these bundles. No app was
launched or modified and no account credentials were read. Version strings below are
installer resource filenames, except BrainViz whose bundle Info.plist confirmed its version.
They establish installed artifacts, not a complete audit of all screens or active entitlements.

| Bundle | Observed installer version | Standalone responsibility |
|---|---|---|
| EMOTIV Launcher.app / EMOTIV-Applet.app | 4.13.3.525.2 | Device connection, status and application entry point |
| EmotivPRO.app | 4.13.3.574 | Recording, review, analysis and export |
| EmotivBCI.app | 4.13.3.333 | Training, profiles and command experiments |
| Emotiv BrainViz.app | 4.13.3.199 | Signal visualization |
| Emotiv Maintenance Tool.app | 4.11.1 installer resource | Installation/maintenance; not an EEG capability |

## One application, one acquisition authority

| Capability | Evidence of vendor offering | Current repository evidence | Standalone target / acceptance |
|---|---|---|---|
| Discovery, connection and disconnect | Installed Launcher and headset screenshot | `stream.py`, `probe_connected.py` | One acquisition service owns BLE; UI shows connected/recovering/stable distinctly. Standalone lifecycle still needs hardware qualification. |
| Hardware identity and mode | EPOC X screenshot and GATT archive | `decoder.py`, `docs/PROTOCOL.md` | Display actual identity/revisions/config; unsupported mode visibly rejected for calibrated delivery. |
| Raw 14-channel EEG | PRO acquisition/review [1] | Direct decoded captures and Cortex comparison | Live traces and unlimited local export subject to explicit storage retention; retain ADC, timing and quality flags. |
| Recording library and playback | PRO recording list screenshot; [1] | JSONL recording, offline parsers | One recording object links raw data, metadata, markers, analyses and exports; incomplete recordings labeled. |
| Export | PRO export modal screenshot | Local JSONL and reference CSV helpers | User-controlled export of our own acquisitions; schema, units and provenance included. Existing helper is not a complete GUI export product. |
| FFT and band power | Official PRO app listing [2] | `analyze_signal.py` and research eye-phase analysis | Reproducible labeled window/filter settings, display-only analysis; no inferred emotions from band power. |
| Sensor contact quality | Contact/EEG quality screenshots | `contact_quality.py` raw values match Cortex | Show raw values now; calibrated contact classes remain unavailable until independently validated. Never show invented 100% quality. |
| Markers and experiments | Research acquisition context [1]; local cue scripts | `research/mark_phase.py`, eye/blink scripts | Monotonic-clock event annotations, audio cues, timestamps and protocol versions attached to recordings. |
| Motion and facial expressions | Official BCI feature list [3] | Auxiliary bytes preserved; no validated motion/expression decoder established | Separate experimental modules only after ground-truth comparisons; blinks are ocular artifacts, not mental commands. |
| Mental command profiles | Official BCI training description [3] | Independent Python/Swift experimental trainer, versioned local profiles, held-out evaluator and receipt CLI; synthetic/reference tests, no qualified participant classifier | Calibrated user profiles, held-out sessions, false-activation measurements and explicit idle state before enabling commands. |
| Cognitive/performance scores | Vendor PRO list includes six named cognitive states [4] | No validated equivalent | Do not imitate proprietary scores. Any independent metric needs its own definition, dataset and validation. |
| Brain visualization | Official BrainViz description [5] | Channel topology known; no source-localization evidence | Scalp channel/band visualization labeled as such; do not imply accurate internal 3D brain activity from a decorative head model. |
| LSL / external research streams | PRO page [1] | No validated LSL bridge in baseline | Versioned optional adapter with time-sync and loss reporting; acquisition remains the single source. |
| Cast / Anika commands | User requirement | No verified EEG-to-intent integration | Explicitly enabled command router with confirmation, cancellation and auditable confidence; disabled until classifier gates pass. |
| Apple accessibility/HID | User requirement | No implemented bridge demonstrated | Separate integration acceptance on supported Apple hardware/software; never claim raw EEG directly conforms to HID. |
| Installer, updates and diagnostics | Installed Maintenance Tool | Source-based Python environment | One signed application/service lifecycle, permission onboarding, sanitized diagnostics; no vendor installer dependency. |

Sources retrieved 2026-09-15, used only for feature categories, not proof of our capabilities:

1. [EMOTIVPRO official product page](https://www.emotiv.com/products/emotivpro)
2. [EMOTIVPRO official App Store listing](https://apps.apple.com/us/app/emotivpro/id1494445214)
3. [EMOTIVBCI official product page](https://www.emotiv.com/emotiv-bci)
4. [EMOTIVPRO official home screen documentation](https://emotiv.gitbook.io/emotivpro-v3/using-emotivpro/emotivpro-home-screen-and-menu)
5. [EMOTIV BrainViz official product page](https://www.emotiv.com/emotiv-brainviz)

Native UI target: SwiftUI on macOS, iOS and visionOS, with shared domain contracts and
platform-specific hardware/permission adapters. These platforms are targets, not validated
hardware support claims. Apple BCI HID is an output-command integration; it does not carry
our raw EEG acquisition stream.

Modern UI requirement: one shell, one device state model, one recording library and one
consistent create/edit/review/export flow. Feature modules consume the same recording and
sample contracts; they must not create separate hidden acquisition paths. Experimental
features must remain visibly experimental and unavailable outputs must not be simulated.
