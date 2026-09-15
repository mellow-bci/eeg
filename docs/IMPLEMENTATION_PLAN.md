# Independent mental-command implementation sequence

Checkpoint: 2026-09-15. Priority is the **independent mental-command workflow**, not an
extension of the earlier eyes/gesture LDA experiment. The capability inventory is versioned
in [`capability-matrix.json`](../capability-matrix.json), schema `eeg.capability-matrix.v1`,
and [PARITY_ROADMAP.md](PARITY_ROADMAP.md). Status applies to the stated subset only.

The first offline processing implementation now exists in `processing/`. It does not ship
a validated participant model and does not enable OS, HID or Cast actions. Earlier
`calibration/` eyes/blink protocols remain a separate ocular/sensory research track; their
cue-associated outcomes are not evidence for the new classifier's neural validity.

## Current native checkpoint (2026-09-15)

The historical checkpoints below describe their state at implementation time; their
“pending” statements are not the current backlog. The native app now has queued
recording writes, acknowledged trial revisions, audible cue scheduling, readiness
controls, review and canonical manifest export. Trial-controller checks include a
complete acknowledged cycle, cancellation and delayed/missing end-cue callbacks.
These are software tests, not physical audio timing or mental-command qualification.

The macOS synthetic dataset import → train → inspect → evaluate → export route
was exercised interactively on build `d63f9de`; see
[the qualification record](qualification/NATIVE_UI_WORKFLOW.md). This supersedes
the historical unresolved-picker note below, but does not qualify live collection.

The next qualification priorities remain:

1. Exercise the complete native workflow on independent real recording sessions,
   with fresh participant readiness and reliable cue delivery. Preserve uncertain
   or missed trials as excluded evidence rather than assigning inferred labels.
2. Evaluate saved profiles on held-out sessions and ordinary-activity controls;
   quantify false activations, latency and artifact dependence before enabling any
   command output. Current inference remains a preview with no control actions.
3. Qualify sustained capture with concurrent processing, reconnection, sleep/wake
   and storage failure. Orderly shutdown can still wait for disk operations.
4. Expand quality, gesture, export and API capabilities against separate measurable
   acceptance criteria. Broader Cortex parity remains incomplete.

`TrialRecoveryTests.testFractionalObservationTimesSurviveRecordingRecovery` covers
100 finalized synthetic trial journals through the actual writer and reader,
checking every recovered event timestamp and dataset start. It uses no headset
samples and establishes serialization fidelity only. Reproduce with:
`swift test --package-path apple --filter TrialRecoveryTests`.

## One workflow and its current state

**Collect → Review → Analyze → Calibrate → inference preview → separately gated output.**
SwiftUI is the native application target and performs acquisition without Python/Cortex.
The offline Python processing service is a research consumer of explicit adapters for
native and Python recordings. Native training, profile inspection and offline evaluation
now exist; prospective physiological and complete interactive workflow qualification remain work.
It must not become a second user-facing setup flow or a competing configuration authority.

1. **Canonical samples and valid windows — implemented, software tests exist.**
   `processing/contract.py` adapts both recording formats into immutable `eeg.canonical.v2`
   samples. `processing/windows.py` makes nonoverlapping 256-sample windows with explicit
   continuity, stability, epoch/configuration and partial-window validity. `workflow.windows_from`
   is the common feature route. Remaining: continue schema/version parity as native capture
   evolves and verify native physical input; software fixtures are not hardware acceptance.
2. **Independent spectral features — implemented and tested synthetically.**
   `processing/features.py` defines 14 channels × five log-integrated-power bands, a
   256-sample Hann/Welch window, linear detrend and explicit flat/rail/amplitude rejection.
   Tests cover known-sine energy and unchanged raw input. These parameters are our own
   experimental design, not recovered vendor defaults. Remaining: artifact-threshold
   validation, prospective signal interpretation and measured end-to-end timing.
   Native `EEGMentalFeatures` now matches all 70 values on a real-recording Python
   oracle within 1e-7 log-power units; native physical readiness remains unqualified.
3. **Profile training — implemented and tested at software level.**
   `processing/mental.py` fits mean/std scaling and between/within-class feature ranking
   on supplied training data only, selects 20 features, projects through up to eight
   train-only PCA components and fits regularized diagonal Gaussian class models with equal
   priors. Training requires neutral plus one or more task labels, at least 20 windows/class across
   at least two sessions, accepted/verified-label declarations and consistent participant
   and feature configuration. These are engineering minimums, not physiological sufficiency.
   This implementation is **not the older `calibration/evaluate.py` LDA baseline**.
4. **Versioned profiles and provenance — implemented and software-tested.**
   Profiles include design parameters, transforms/statistics, participant, training window
   IDs, session-to-canonical-recording hashes and optional parent profile. One content hash
   per session and distinct hashes across training sessions prevent full-recording reuse
   under different names. Private exclusive saves, checksum/dimension/design validation and
   detector deep copies are tested. Checksums detect modification, not malicious provenance
   forgery; declarations do not independently prove acquisition independence or task compliance.
5. **Neutral, rejection and inference persistence — implemented and software-tested.**
   The detector rejects invalid/artifact/config/participant mismatches, ambiguous scores,
   excessive modeled-space distance and insufficient persistence. Two consecutive accepted
   nonoverlapping windows are required; gaps and rejected inputs reset the pending candidate.
   Scores are uncalibrated. PCA-space distance does not detect every possible artifact or
   out-of-distribution input. Every proposal remains `command=null`,
   `system_control_enabled=false` and `status=no_reliable_command`, even when an
   `experimental_candidate` is available for analysis. No processing score unlocks output.
6. **Whole-session evaluation — implemented, real acceptance evidence still required.**
   `processing/workflow.py` exposes extract/train/evaluate/replay through the shared window
   path. It validates declared trial intervals and separates train/evaluation sessions;
   evaluation rejects overlapping session IDs, windows or canonical recording content.
   Reports preserve rejection outcomes, class metrics, cued-neutral exposure and processing
   time. Window results within a trial are correlated; cued-neutral false-positive windows
   are not ordinary-activity false activations/hour. Remaining: independently verified
   mental-task/neutral labels from genuinely separate acquisitions, an untouched future
   session after headset reapplication, artifact controls and representative neutral exposure.
7. **Native trained-inference workspace — implemented subsets, qualification incomplete.**
   Swift training, profile persistence/inspection, finalized-recording dataset loading,
   labeled evaluation and receipt export use EEGCore. `EEGEvaluate` shares the app's
   evaluation entry point; the CLI is a reproducibility interface, not another pipeline.
   Synthetic/reference tests cover these components. Saved-profile inspection and the
   controls-only toggle were exercised in the native UI. The external file picker remains
   unresolved, and the full native training/evaluation flow has not passed interactive
   acceptance. Next priorities are a usable native cue/label-evidence workflow, explicit
   cancellation and interruption handling, then fresh-participant prospective sessions
   under `MENTAL_QUALIFICATION_PROTOCOL.md`. No prior ready message or uncertain eye-test
   labels may stand in for those sessions. Physical timing and long-session durability
   remain gates; software agreement does not establish mental-command accuracy.
8. **Controlled output — disabled, acceptance pending.**
   Only after prospective scientific and hardware gates: explicit arming, neutral/abstention,
   confirmation, expiry, cancel/kill switch and a reversible local test action. Neural claims
   require controls showing that successful predictions are not merely blinks, jaw tension,
   head movement or cue timing. Apple HID/Cast adapters require their own platform tests.
   No EEG sample or band-power threshold directly executes system-wide actions.

Implementation details and reproduction commands are in
[MENTAL_WORKFLOW.md](MENTAL_WORKFLOW.md). Selected vendor body evidence is separately
recorded in [MENTAL_REFERENCE_TRACE.md](MENTAL_REFERENCE_TRACE.md): actual call sites support
parts of the feature-selection/PCA/canonical/Gaussian/posterior architecture, while complete
raw-to-feature ordering, model assets and numeric behavior remain unresolved. Our code
implements its declared independent design, not those unknown parameters or vendor assets.

## Immediate next work

First complete prospective mental-task data collection and evaluation, only after current
participant readiness and an explicitly defined task/protocol. Preserve requested labels,
observed behavior and predictions separately; uncertain-cue sessions must not be promoted
to verified training data. Use [COGNITIVE_VALIDATION.md](COGNITIVE_VALIDATION.md) for
trial/session holdout, neutral exposure, uncertainty and artifact-control gates. Do not
reuse an eye/blink classifier result to satisfy this mental-task requirement.

In parallel, finish native inference/profile integration and acquisition/recording
qualification against the same contracts. Physical headset startup, battery interruption,
sleep/wake and mobile background behavior still need actual hardware; replay cannot
substitute for them. Signed distribution and native persistence/throughput qualification
remain independent release requirements.

## Subsequent breadth and completion discipline

After the first complete independent mental workflow, extend native analysis, validated
contact quality, EDF interoperability and additional hardware through existing service
adapters. New cognitive constructs require their own independent definitions and studies,
not a vendor score name. Firmware changes and vendor model assets remain out of scope.

Enterprise RBAC, audit and encrypted sync are **planned opt-in services**. They must share
canonical object permissions, support revocation/deletion and preserve local capture/export
without a subscription. They are not presently built.

Use only `discovered`, `understood`, `implemented`, `tested`, or `hardware-validated` in the
matrix. `tested` in current mental-processing rows means synthetic numerical, validation
and state-machine checks, not a trained participant or hardware-qualified mental command.
Attach source/test/report identifiers when promoting an entry and retain explicit missing
parameters/data/dependencies. Report what was trained, whose sessions were held out,
how labels were verified and which outputs remain disabled. An attractive UI, class-name
inventory, successful build or completed audio-cue sequence is not scientific validation.

## Availability policy

[PRODUCT_CAPABILITY_POLICY.md](PRODUCT_CAPABILITY_POLICY.md) is a release requirement: one unified application, no subscription tiers or artificial capture/export/training restrictions. Useful service capabilities are independent implementations. Technical validity, permissions and real resource budgets remain explicit; vendor licensing is not part of the runtime.

Supported classifier tuning now uses [PROCESSING_SETTINGS.md](PROCESSING_SETTINGS.md); complete settings are frozen in v2 profiles. The native editor remains pending. Shadow evaluation now separates explicit ordinary-activity/control conditions from cued neutral and preserves proposal episodes, carry-in and exposure; physiological qualification is unchanged.


## CI compatibility checkpoint

[Run 34908821255](https://github.com/autonomy-cloud/eeg/actions/runs/34908821255)
passed for `3fe3c9b`: Python regressions, native tests, native profile loading in
Python, and native CLI receipt comparison. Earlier revisions failed to compile
an overloaded concatenation expression in `TrainingDataTests` on the runner's
Swift compiler. The assertion now compares explicit vectors/rows and verifies
lengths before element comparisons. No numerical tolerance was relaxed.
This checkpoint does not qualify live hardware or physiological performance.

## Native recording abort semantics

The acquisition model now aborts the existing recording on storage errors,
including startup metadata, transport checkpoints and annotations. Abort closes
without writing a completion summary; existing samples remain reviewable, but
finalized-dataset analysis rejects the unfinished recording. Sample write errors
and generic event serialization/write errors also close the writer internally.
Normal user stop still finalizes a healthy recording. A new recording can start
explicitly after an abort; the failed file is never resumed automatically.

Regression coverage exercises explicit abort, retained sample replay, analysis
rejection, restart into a distinct file and oversized-event failure. These tests
are not disk-full, forced-kill or power-loss qualification. The completion-summary
write/synchronize boundary still needs failure-injection qualification. Native
trial cue/controller integration remains pending; this fixes its recording
failure prerequisite without creating another acquisition path.

## Trial lifecycle bridge

`EEGTrialSession` now commits transitions through the existing recording sink
before publishing them. Acquisition owns one instance per recording and passes
`systemUptime - origin`, the same clock used for sample receipt timestamps.
Transport loss and normal stop interrupt unfinished trials. A failed evidence
write invalidates the in-memory trial, exposes a persistence error and prevents
retry on that session; the interruption itself may be unpersisted, so it is not
claimed as durable evidence. The recording abort path preserves the original file.
Invalid operator transitions do not write events or poison an otherwise healthy
recording. These are independently designed lifecycle rules, not recovered vendor
algorithms. The host currently serializes acquisition and evidence calls on the
main queue; moving recording I/O off that queue remains a responsiveness task.

Unit tests cover ordered publication, interruption idempotence, sink failure,
retry rejection and invalid transitions. Native audible cue scheduling, fresh
readiness controls, trial review UI and manifest generation remain pending.
No physiological trial was performed by this change.

## Completion-write failure handling

The recording writer now saves its byte offset before appending a completion
summary. A summary write or synchronization failure attempts to truncate back to
that boundary and synchronize, preserving prior measurements without a success
marker. If rollback also fails, `EEGRecordingCompletionFailure` exposes both
errors and explicitly reports uncertain completion. A close error after successful
summary synchronization remains an error; it does not undo already-synchronized
bytes. Forced kill, filesystem failure and power loss are still qualification gates.

An internal output interface wraps the same securely opened local FileHandle.
Tests substitute a wrapper around a real temporary file to inject a partial
summary write, a summary flush failure, and rollback failure. No production mock
acquisition or alternate sample source was introduced. Tests verify prior event
retention, incomplete/noncorrupt status after successful rollback, rejected
analysis and explicit uncertainty when rollback fails. If storage prevents all
rollback writes, on-disk completion may remain ambiguous; the returned error is
not a guarantee that a future reader can detect that failure independently.


## Shared evaluation cancellation checkpoint

The canonical receipt constructor now rejects cancelled tasks and checks long
prediction/trial conversion plus the JSON serialization boundary. A regression
failed before the fix and passes with byte-identical independent retry output.
See [EVALUATION_CANCELLATION.md](EVALUATION_CANCELLATION.md) for the observed core
gap, existing UI publication guards and cooperative-cancellation limits. No
acquisition, model or control-output behavior changed.
