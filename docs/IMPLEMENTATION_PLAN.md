# Independent mental-command implementation sequence

Checkpoint: 2026-09-15. Priority is the **independent mental-command workflow**, not an
extension of the earlier eyes/gesture LDA experiment. The capability inventory is versioned
in [`capability-matrix.json`](../capability-matrix.json), schema `eeg.capability-matrix.v1`,
and [PARITY_ROADMAP.md](PARITY_ROADMAP.md). Status applies to the stated subset only.

The first offline processing implementation now exists in `processing/`. It does not ship
a validated participant model and does not enable OS, HID or Cast actions. Earlier
`calibration/` eyes/blink protocols remain a separate ocular/sensory research track; their
cue-associated outcomes are not evidence for the new classifier's neural validity.

## One workflow and its current state

**Collect → Review → Analyze → Calibrate → inference preview → separately gated output.**
SwiftUI is the native application target and performs acquisition without Python/Cortex.
The new offline Python processing service is a research consumer of explicit adapters for
native and Python recordings; native trained inference and its UI integration remain work.
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
   validation, prospective signal interpretation, native port and measured end-to-end timing.
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
7. **Native trained-inference workspace — pending.**
   Port the explicit feature/model/profile contract into native code and match fixed Python
   golden vectors. Then expose collect/review/train/evaluate/preview through the existing
   native recording and Calibration workspace. Verify bounded delivery, profile lifecycle,
   invalid-data states and physical-device timing. No claim of a complete native mental
   command app follows from the offline CLI implementation alone.
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
