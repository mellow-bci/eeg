# Live EEG timing and runtime composition — 2026-10-11

Reference binary arm64 CortexService SHA256 cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a. Existing complete body captures in timestamp-clock-continuation-20261011 are reused, not inferred from names. No vendor model/credential asset is required or bundled.

## Live startup/reset composition

ReferenceLiveTimestampWorkflow composes the existing timestamp kernels for explicitly supplied type16 EEG packages, mode7 semantics, positive epoch-steady observation and explicit configuration. It is not a hardware decoder or an implementation of special modes6/9/10/11. Unsupported mixed packets fail explicitly. Source packets remain with caller; output exposes retained indices, pre-offset timestamps, corrected timestamps, reanchor flag and local reference error21/22 outcomes.

Body `process` 0x101073310, constructor-process.txt:
- Empty list returns0 before any clock mutation.
- 0x101073470..480 checks absolute observedTime−unroundedEEG > maximumDeviation; strict equality passes.
- 0x1010735c4..5d4 resets ready=false, pendingOrigin=true, pendingAnchor=true, firstMotion=true. EEG-only wrapper has no motion package processor.
- 0x1010735e4..628 sets origin once then holds until elapsed>=warmup. Warming stores current unrounded EEG time and returns21; does not process/consume packets into a downstream signal window.
- 0x101073658 calls addFirstTimestamp. Its full body selects last EEG, rejects lastPreOffset>=current with reset flags/error21, resets cumulativeDistance=1 and updates origin. It does not clear timestamp history/correction counters. Clock.reanchor now preserves those fields.
- addTimeStamp processes retained anchor again (distance0, history insertion), processes later batches with nominal or prior adaptive rate, updates adaptive rate from POST-batch count.
- syncTimestampAndRealTime changes clock state, not already emitted packet timestamps. removeBadCounterSample tests emitted packet times, requests reset/error22; hardware offset runs only after success. Failed22 retains preceding clock mutations but returns no corrected output.
- Hardware timing saves last pre-offset EEG independently, before subtracting the explicit hardwareOffset from output.

Independent policies: finite and bounded input; invalid/unsupported arithmetic exceptions atomically preserve wrapper state; UInt32 overflow rejected; negative elapsed rejected. Error21/22 outcomes intentionally preserve state transitions. These policies are documented differences, not vendor recovery claims.

## Epoch-steady source

ReferenceEpochSteadyClock follows captured timeutils.txt: steady nanoseconds truncated to microseconds (signed constant-division sequence), converted to double seconds, multiplied back, truncated to integer, divided again. System clock input is explicitly microseconds. Epoch observation preserves `(epochAnchor + currentSteady) - steadyAnchor` evaluation order. Positive supplied time bypasses fallback. Actual platform clock reads and which upstream caller supplies time are not inferred; this pure adapter accepts observations for deterministic tests/replay.

## Canonical fitting

training-followup-20261010/pca-canonical.txt 0x100b4a128..140 passes "dc" into the shared eigensolver wrapper. ReferenceCanonicalTraining now uses ReferenceNumericalLeaves divideAndConquer/fallback instead of its old direct dsyev. Scalar Cholesky/whitening, sign convention and dimension limit remain declared independent implementation choices. Repeated eigenspaces/linked LAPACK differences still require oracle evidence.

## Runtime recipe bridge

ReferenceResolvedMentalWorkflow resolves already-converted profile settings through ReferenceRuntimeRecipe, applies explicit input-channel IDs to row selection and delegates to ReferenceRawMentalWorkflow. No duplicate filtering, FFT, classifier or scoring implementation. Caller still supplies reference-scale CQ and trained runtime; neither vendor profile selection nor hardware quality is manufactured. Full matrix shape/finite validation including unused channels is an independent fail-closed policy.

## Qualification boundary

Authored deterministic tests prove implementation behavior and composition, not output equality with Cortex. Trained profile and synchronized intermediate/final output fixtures remain required. No participant experiment is performed in this work. Motion/mixed packet paths, physical clocks/reconnect, SQ learned assets and device qualification remain separate gates. Output remains diagnostic; no application/OS actions.

## Timing-to-signal integration

ReferenceTimedMentalWorkflow feeds only successful retained samples into the resolved workflow. It preserves full original packets and timing provenance. It validates sample-rate compatibility and measurement shape before atomically advancing both states. Warmup/error21/error22/reanchor reset downstream filters/windows/background/scoring as our explicit discontinuity policy; this is not recovered vendor manager.stop behavior. Empty transport batches do not drain inference backlog. No implicit packet interpolation, CQ metadata conversion or trained model.

Canonical inverse integration now routes the lower Cholesky factor through ReferenceInverseDispatch, replacing the former scalar inverse loop. Tests check generalized eigen residuals for dimensions3,4,5, in addition to existing2D fixtures. Lower-factor orientation, scalar Cholesky and final solve remain independent algebra choices; this is not bitwise vendor equivalence. See inverse-dispatch-20261011 for exact small leaves, SPD heuristic and LU paths.

## Executed validation

Full package run before final continuity gate:569 executed,565 passed,4 skipped,0 failures,155.410s. Final reference-focused run after continuity gate:354 executed,352 passed,2 skipped,0 failures,2.901s. Logs retained here. Missing reference/export fixtures and opt-in host-load tests remain explicit skips; no hardware/reference comparison is claimed.

Final continuity policy: packet-counter gaps or duplicates reset downstream uniform-sample analysis, preserve all originals/timing, reject the entire signal batch, and establish its last counter as the next baseline. Contiguous wrap and explicitly supplied contiguous interpolated rows remain admitted. No missing measurements are fabricated. Tests cover rejection, recovery and filter-window reset.

## Remaining qualification, not silently completed

The supported EEG-only comparison path is now wired through timing, profile recipe resolution and diagnostic inference. Mixed/special motion routes and native device lifecycle are not implemented by this wrapper. Actual loaded Cortex recipe/model and aligned intermediate outputs, linked-LAPACK/ill-conditioned numerical oracle tests, real quality-channel observations, hardware time/reconnection and prospective artifact-controlled trials remain required. Stricter finite/bounds/discontinuity rules are independent policies; exact behavior on arbitrary vendor-invalid inputs is not claimed.
