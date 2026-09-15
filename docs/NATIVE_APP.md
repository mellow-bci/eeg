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

### Native PCA and Gaussian fitting

`EEGMentalTraining.fit` calls the training eligibility/preparation path, then uses
Accelerate LAPACK `dgesvd_` for thin right singular vectors. Column-major storage,
workspace query, dimensions and decomposition status are checked. The selected
component count is `min(configured components, records - classes, selected features)`.
Each component's largest absolute coefficient is made positive, matching the Python
sign convention. It then projects training records, fits per-class population means
and diagonal variances with the configured floor, and sets the distance limit to
`max(4 * dimensions, 1.5 * linear 99th percentile of training distances)`.

Apple's [SVD sample](https://developer.apple.com/documentation/accelerate/compressing-an-image-using-linear-algebra)
documents the LAPACK storage/workspace pattern; the implementation also follows the
installed SDK's double-precision function declaration. It does not use vendor assets.
The fit returns scoring parameters, not a published profile or action authorization.

The extended manufactured Python fixture contains expected fitted parameters. Native
components, Gaussian parameters and resulting scores match within 1e-8 locally.
Tests cover wide and degenerate matrices through orthonormality and reject malformed
or nonfinite matrices. Degenerate singular subspaces can have different equally valid
bases across numerical backends; exact serialized parameter identity is not promised.
SVD failure is explicit. Profile serialization/provenance, native trial collection,
held-out evaluation UI and physiological qualification remain required.

The Swift package enables `ACCELERATE_NEW_LAPACK` through the Clang importer and
uses `__LAPACK_int`, avoiding the deprecated CLAPACK interface. This is a compiler
header selection, not an alternate processing path. The local numerical tests pass
with that interface enabled.

### Native versioned profile creation and storage

`EEGProfileCreation.train` connects native eligibility, normalization, selection, PCA
and Gaussian fitting to an `eeg.mental-profile.v2` artifact. It records the complete
settings/design snapshot, participant, training sessions/content fingerprints/window
identities, digest of the encoded training records and optional parent profile ID.
The parent ID is checked for format; its lineage relationship remains a caller assertion.
Every artifact remains experimental with system control disabled. The existing native
loader validates the created artifact before it is returned.

The serializer emits ASCII string escapes and finite numeric tokens compatible with
the Python checksum convention. The synthetic native profile (including Unicode
participant text) passes `processing.mental.load_profile` without modifications.
That cross-runtime check now runs in CI after Swift tests. Matching serialization
is tested for the supported artifact values; it is not a universal canonical JSON
standard or an authentication signature.

`save` writes and synchronizes a private temporary file, then publishes it with a
same-directory hard link that fails if the destination already exists. It cleans up
the temporary name and never overwrites an existing profile. It does not yet fsync
the parent directory, so power-loss directory durability remains unqualified.
Tests verify roundtrip integrity, deterministic repeated fitting on the current
backend, parent ID validation, mode 0600 and overwrite rejection.

Reproduce the cross-runtime check:

```sh
EEG_NATIVE_PROFILE_TEST_EXPORT=/tmp/eeg-native-created-profile.json swift test --package-path apple
python -c "from processing.mental import load_profile; load_profile('/tmp/eeg-native-created-profile.json')"
```

This is a core API, not yet native trial-collection/training UI. Supplied feature
records contain assertions; the app must derive them from validated recordings and
accepted trials before presenting training as a complete workflow. No hardware or
physiological qualification follows from this synthetic profile.

### Recording-backed native training action

Calibration now has **Train from recorded trials**. Open an `eeg.dataset.v1` JSON
manifest, then explicitly select **Train and save experimental profile**. It reads
saved Processing settings, validates recordings and trial declarations, fits the
native classifier and writes `Application Support/EEG/Profiles/<profile-id>.json`.
The profile can then be opened in the existing inspection/offline-inference panel.
Work executes away from the main thread and the action is disabled during capture
or an active headset session. Existing profile files are not overwritten.

`EEGTrainingDataset` resolves recording filenames only within the local recording
library. It validates every declared session, including evaluation files, with the
same recording/window/feature functions. It rejects duplicate session IDs, reused
canonical EEG content across any splits, overlapping or uncertain trials, unsupported
conditions and trials containing no windows. Only eligible training windows enter
the fit; invalid/artifact windows are counted. Evaluation windows never enter the
training records. This is stricter than the Python loader for an empty training
trial: the native loader rejects it rather than silently omitting it.

The existing manifest fields are used: `schema`, `participant_id`, `sessions`; each
session has `id`, `recording` (library filename), `split` (`train`/`evaluation`),
`independent_session: true`, and `trials`. Each trial supplies `id`, `label`, `start`,
`end`, `accepted: true`, and `label_verified: true`. Times use recorded arrival
seconds. Optional condition/shadow/cue fields follow the existing dataset contract.
An entire window must fit within a trial, using its first and last arrival times.
Native replay's end timestamp was aligned to that same last-arrival convention.

Keep the source manifest and recordings: this action currently saves the profile,
not a complete reproducibility bundle. Interactive trial editing, a native cue runner,
cancellation/progress by stage, labeled evaluation reports and hardware qualification
remain. The UI import/save flow still needs interactive accessibility testing.

The end-to-end synthetic test creates two distinct training recordings plus a third
evaluation recording, derives 40 training feature windows, fits a native profile and
runs held-out replay. It checks that evaluation session IDs never enter the profile.
These manufactured sinusoids test wiring and leakage rejection, not mental commands.

### Native labeled held-out evaluation

Loaded profiles now expose **Evaluate labeled sessions**. The selected dataset's
recordings and trials pass through `EEGTrainingDataset`; evaluation windows retain
feature validity, trial identity, condition, shadow state and observed time fields.
Only feature vectors/metadata are retained, not all raw window samples. The native
evaluator rejects training session/content overlap and requires ten evaluation windows
per profile class. It preserves chronological order and rejects invalid timing.

A neutral prediction requires the detector's explicit neutral result. Invalid input,
artifacts, disabled trials, ambiguous scores and other rejection states remain null
predictions. Per-class TP/FP/FN, precision/recall and rejection fraction include those
windows; undefined precision is shown as unavailable. Labels named `reject` are not
confused with a rejection because the native result uses optional labels.

The manufactured Python evaluation fixture includes an artifact window and a disabled
window. Native predictions and metrics match `processing.workflow.evaluate_profile`.
Generate it with `python tools/generate_native_evaluation_fixture.py`; runtime timing
measurements are deliberately omitted from the fixture. No live evidence is added.

This is the window-metric portion of evaluation. Native episode onset rates, ordinary
activity exposure accounting, Poisson uncertainty, cue-relative latency, controls-only
mode, reproducible report export and interactive accessibility checks remain incomplete.
Window counts are correlated observations, not independent participants. Every report
keeps hardware validation and system control false.

### Native activation episode accounting

Labeled evaluation now separates candidate windows from rising-edge episodes by
condition. Same-label candidates in the same session/continuity segment, separated
by at most 0.05 seconds, remain one episode. Rejection, disabled input or a gap ends
that continuity. A candidate whose evidence starts before the trial, or continues
into a new trial, is counted as carry-in rather than a fresh onset.

Eligible, signal-rejected and unarmed seconds are reported separately. Empirical
onsets/hour use eligible seconds only and are unavailable with zero eligible exposure
or carry-in candidates. The UI shows these values for each declared condition;
cued neutral is never relabeled ordinary activity. Candidate counts remain experimental,
not evidence of neural origin. Rates currently have no native uncertainty interval.

The Python evaluation fixture agrees on exposure, episode counts and rates. Dedicated
synthetic tests cover repeated candidates, trial carry-in, rejection/disabled exposure,
new episodes after rejection and invalid evidence timing. Prospective ordinary-activity
recordings, latency, uncertainty and physiological artifact controls remain required.

### Native cue-relative trial timing

Evaluation now retains one timing record per session/trial. A new matching task
candidate receives cue-associated latency only when its accumulated evidence starts
at or after the recorded cue completion. Latency is last input arrival minus cue
completion. Repeated candidates and pre-cue evidence are not credited as new responses.
A missing cue produces unavailable timing/detection status, rather than zero latency.

Trial duration minus covered window duration is reported as unobserved seconds.
It is not counted as successful neutral exposure. Conflicting trial metadata and
invalid containment/timing are rejected. Tests cover pre-cue persistence, a subsequent
eligible onset, absent cues and conflicting metadata; fixture trial coverage agrees
with the Python evaluator. These measurements do not establish physiological onset,
user compliance or end-to-end live latency. Uncertainty and prospective qualification
remain outstanding.

### Native episode-rate uncertainty

Condition exposure now includes the one-sided 95% Poisson upper rate used by the
Python evaluator: `chi2.ppf(.95, 2*(onsets+1))/2 * 3600/eligible_seconds`. Zero onsets
therefore retain a positive upper bound. No eligible exposure or carry-in candidates
produce an unavailable result. This is a constant independent-event-rate model,
not participant-level uncertainty or proof of physiological reliability.

`EEGPoissonBound` inverts the Poisson lower-tail probability of .05 using a descending
term recurrence and bisection. It uses a Stirling correction above small counts to
avoid cancellation of large log-factorials. Invalid inputs, unrepresentable integer
counts or numerical nonconvergence return unavailable; no approximate success is
substituted. The recurrence is bounded at 100,000 terms and bisection at 100 iterations.
These are numerical convergence guards, not dataset or subscription limits.

Tests compare counts from zero through one million with SciPy's chi-square oracle,
including the small-count/Stirling boundary, with relative tolerance 1e-10. Existing
condition fixtures also match Python's upper rates. See the [SciPy Poisson definition](https://docs.scipy.org/doc/scipy/reference/generated/scipy.stats.poisson.html).
Clustered/temporally dependent activations can violate the model; prospective ordinary
activity and artifact-control trials remain required. This bound does not qualify
system control or mental-command accuracy.

### Controls-only evaluation scope

The evaluation panel now offers explicit controls-only mode, matching the Python
workflow's scope. It accepts only neutral-labeled cued-neutral, ordinary-activity,
blink, jaw and head-movement controls. It rejects any task trial. Full evaluation
still requires ten windows per class; controls-only does not fabricate task coverage
or recall. The report stores and displays its scope, and changing the toggle clears
the previous report. Session/content exclusion, rejection accounting and experimental
control-disabled status apply identically in both modes.

Tests establish that a neutral-only dataset fails full evaluation, passes controls-only,
has unavailable task recall, and that mixed task/control data fails controls-only.
No control condition has been prospectively validated by these synthetic tests.

### Interactive calibration check (2026-09-15)

The current macOS build was launched without acquisition and the Calibration
screen was inspected through the accessibility tree. Training and profile-opening
controls rendered. Removed stale empty-state and Processing help text that said
native training/evaluation did not exist; those workflows are implemented but
remain experimental and physiologically unqualified.

Profile import did **not** pass this interactive check: the automated macOS file
panel displayed the repository's synthetic `mental-profile.json` as selected while
Open remained disabled. Explicit single-selection, a broader data-type filter,
and an explicit AppKit panel did not resolve the observed behavior. Those
experimental picker changes were reverted. This does not establish the cause
(application, OS, or automation); an ordinary manual import and an automated UI
regression check remain necessary. No profile was loaded in this UI run and no
training/evaluation success is claimed from it. Core tests and prior Python
interop checks do not replace this missing UI qualification. No headset recording,
Cast changes, or vendor-runtime dependency was introduced.

### Saved profile library and training handoff (2026-09-15)

Calibration now owns the selected profile. After native training, `EEGProfileStore`
saves through the existing exclusive private writer, reopens the persisted bytes,
checks their v2 integrity and filename identity, then hands that profile directly
to inspection/evaluation. Save or read-back failure produces an error instead of
handing an in-memory fit to the evaluation UI. Existing files are not replaced.

The local `EEG/Profiles` library lists metadata, with explicit Refresh and Inspect
controls. Inspect uses the same bounded reader as external profile import:
regular files only, final-component symlinks rejected, maximum 8 MiB, followed by
canonical profile validation. Library filenames must match the 64-character
lowercase hexadecimal profile ID. A malformed library entry currently causes a
visible library error; listing itself does not certify contents. The existing
parent-directory trust and power-loss durability limitations still apply.

Verification: 71 Swift tests passed, including save/read-back, refusal to replace,
corruption, filename mismatch, traversal identifiers, symlink, directory and size
checks. macOS, iOS Simulator and visionOS Simulator builds passed. In the running
macOS app, a temporary copy of the synthetic scoring profile was listed, inspected,
and displayed as experimental with command output disabled. The controls-only
evaluation toggle changed its scope description correctly. The temporary fixture
was removed afterward. No EEG acquisition or physiological experiment occurred.
The full train-from-manifest UI sequence and external file-picker problem remain
unqualified; the saved-library check is not proof that those paths work.

### Evaluation receipt export (2026-09-15)

The labeled evaluator now produces `eeg.native-evaluation.v1` through
`EEGEvaluationArtifact.run(manifest:store:profile:controlsOnly:)`. The public entry
point loads the manifest and original recordings, runs the existing canonical
feature/detector/evaluation path, and serializes that result. The UI retains this
artifact together with the displayed report; changing scope or starting a new
run discards the previous artifact. Export evaluation JSON uses the native save
panel. Nothing is uploaded.

The receipt contains exact manifest bytes (base64) and their SHA-256, profile ID,
feature configuration ID, processing settings, source file and canonical EEG
hashes for every loaded session, per-window timing/continuity/labels/rejections,
class counts and precision/recall, condition exposure and episode rates/bounds,
and trial coverage/cue latency. Unavailable values are JSON null; a rejected
prediction is never rewritten as neutral. The versioned metric definitions and
limitations travel with the result. Algorithm version `native-labeled-evaluation-1`
identifies the receipt's metric semantics; it is not a hardware qualification.

This is a receipt, not a full archive. Reproduction still requires the matching
profile and original recordings. Decode `manifest_base64`, verify its SHA-256,
load the referenced sources in the recording store, call the same public entry
point with the saved scope, and compare the source hashes before interpreting
metric differences. Preserve the receipt with its referenced files. Hashes are
integrity identifiers, not signatures or proof of physiological labels.

Reproduction checks:

```sh
swift test --package-path apple --filter TrainingDatasetTests.testRecordingsAndLabelsTrainNativeProfileWithoutEvaluationLeakage
swift test --package-path apple --filter LabeledEvaluationTests.testReceiptKeepsUnavailableValuesAndRejectionsExplicit
```

The first test executes synthetic recordings through profile training and receipt
production, verifies exact manifest recovery and both source hash types, and
rejects a malformed manifest. The second verifies deterministic serialization,
controls-only scope, null task recall, missing cue timing and explicit rejection.
The full Swift suite passed 72 tests. The native save panel itself has not been
interactively qualified; the previously documented external picker problem and
physiological evaluation gates remain open.

### Recording stability during reads (2026-09-15)

The shared bounded recording reader now captures device/inode, size and
nanosecond modification/change timestamps from the open file descriptor before
reading. Before returning a successful digest it compares those values again and
checks that the named path still identifies the same regular file. A mismatch
throws `sourceChanged` with a retry message. This applies to analysis, replay,
inventory and CSV export because they share this reader. Inventory marks a failed
read unavailable/corrupt; CSV removes its failed partial destination. Analysis
callbacks remain provisional until the whole method succeeds.

The change prevents silently accepting an appended prefix, a detected same-length
edit, or an atomic path replacement during analysis. It does not lock the file,
create an immutable snapshot, authenticate its owner, or prevent later edits.
The saved source digest remains necessary when reproducing a result. A file being
actively written can now fail review rather than presenting a changing prefix.

`AnalysisWindowTests.testConcurrentSourceChangesRejectProvisionalAnalysis`
mutates a synthetic recording during the first analysis callback: append,
same-length rewrite (with an explicitly changed mtime), and same-content atomic
replacement. Each fails with `sourceChanged`. These are deterministic filesystem
checks, not a radio-interruption or hardware-durability qualification.

### Native evaluation command line (2026-09-15)

`EEGEvaluate` is a macOS Swift package executable over the **same**
`EEGEvaluationArtifact.run` entry point used by the app. It adds no preprocessing,
classifier or metric implementation. It reads an existing recording directory,
a validated profile and a bounded regular-file manifest, then writes the complete
JSON receipt to stdout. No acquisition or vendor process is started. Argument
errors exit 2; evaluation/I/O failures exit 1 and report on stderr. Evaluation
failures emit no provisional JSON. As with any stream, a broken output pipe can
interrupt writing; consumers must check exit status and parse the complete JSON.

```sh
umask 077
swift run --package-path apple EEGEvaluate \
  --manifest /absolute/path/manifest.json \
  --profile /absolute/path/profile.json \
  --recordings /absolute/path/Recordings > /absolute/path/evaluation.json
```

Use a new destination filename: shell redirection can overwrite an existing file.
Add `--controls-only` only for a neutral-labeled control dataset; it does not waive
label, source-integrity or leakage checks. `--help` documents the interface. The
recording directory must already exist; invalid arguments do not create one.

`python3 tools/check_native_evaluation_cli.py` generates temporary synthetic
recordings through the native test, executes the CLI, and compares the receipt
byte-for-byte with the canonical evaluator's output. The fixture has two training
and two held-out synthetic recordings, with 40 evaluation windows. Python also
recomputes per-session eligible/rejected/unarmed durations and candidate counts
from exported window rows and checks pooled counts equal session totals. This is
an independent accounting check, not a second classifier or physiological oracle.
It checks wrong flags,
duplicate arguments, a mixed-task dataset in controls-only mode and a malformed
manifest: each must fail with stderr diagnostics and no stdout receipt. Temporary
fixtures are removed by the test script. CI runs this check; synthetic agreement
is not physiological validation or completion of interactive app qualification.


## Session-specific evaluation exposure

Evaluation algorithm `native-labeled-evaluation-2` adds `session_conditions` to the
existing `eeg.native-evaluation.v1` receipt. Keys are recording session IDs and
condition names. Each entry uses the same exposure fields as pooled `conditions`:
eligible, rejected and unarmed seconds; candidate windows; episode onsets;
carry-ins; empirical rate and conditional Poisson upper bound. The native results
view exposes these under “Results by session”, using the same presentation as
pooled conditions. Existing pooled fields remain unchanged.

One episode-accounting pass produces each window's contribution and accumulates
it into both summaries. It does not rerun inference independently per session or
change classifier parameters. A carry-in invalidates the affected session's rate
and the pooled rate; another session with no carry-in retains its own estimate.
This makes variability inspectable, but does not establish cross-session robustness.
Short exposures remain weak evidence, and correlated events violate the simple
Poisson assumption. No control output is enabled by this addition.

Regression coverage uses distinct quiet and active synthetic sessions, including
rejected exposure and a carried candidate, and checks receipt serialization.
No live acquisition or physiological experiment was performed.

Validation: 131 tests, one opt-in qualification skipped, zero failures. Native
macOS, iOS and visionOS builds passed. Interactive layout validation is pending.


## Calibration and evaluation rejection guidance

The core dataset, training-data and labeled-evaluation error types now provide
localized descriptions consumed by the native training/evaluation views. Messages
explain insufficient class/session coverage, duplicated content, incompatible
features, invalid trial evidence, processing limits and training/evaluation overlap.
The technical error case remains visible in brackets for reproduction. This is a
presentation change; validation thresholds, classification and save behavior are
unchanged. Uncertain labels must be excluded, not made valid merely to pass a gate.
The profile remains experimental and cannot enable system control.

Validation: 131 tests, one opt-in skip, zero failures; macOS, iOS and visionOS
builds passed. No hardware trial or interactive error-layout check was performed.
