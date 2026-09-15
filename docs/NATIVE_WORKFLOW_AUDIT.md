# Native mental-command workflow audit — 2026-09-15

Code checkpoint: `b0f6d90`. This audit preserves the complete feature-parity goal;
it does not redefine completion as the pieces implemented below.

| Requirement | Current code/evidence | Unfinished proof or work |
|---|---|---|
| Independent acquisition | `AcquisitionModel.swift`, `Decoder.swift`; original notifications and decoded samples retained | Fresh physical native EPOC X start/reconnect/sleep-wake qualification; supported mode only |
| Planned task evidence | `TrialCueController`, `TrialSession`, `TrialPlan`, `TrialEvidence` and their core tests | Speech/UI handling has compiled but not been interactively or acoustically qualified |
| Recorded labels | Recording-store revision recovery validates plan, order, rest and timing | Declarations are not physiological ground truth; observations default unknown |
| Dataset preparation | `TrialDatasetExport` and `DatasetBuilderView`; synthetic recording-to-window test | Real independently acquired sessions; interactive selection/export check |
| Personalized training | `MentalTraining`, `ProfileCreation`, `ProfileStore`; reference-vector and cross-language tests | Participant-specific prospective calibration/acceptance and artifact robustness |
| Held-out evaluation | `LabeledEvaluation`, `EvaluationArtifact`, prepared-manifest UI | Real whole-session precision/recall, false activations, latency and cross-session evidence |
| Live inference | `ReplayInferenceView` invokes offline `EEGReplayInference.run`; acquisition contains no profile-inference consumer | Implement live shadow processing through canonical windows and detector; persist provenance/results without actions |
| Controlled output | `EEGExperimentalProposal` always has nil command and disabled control | Keep disabled until qualification and a confirmation/cancel policy; no actionable output claim |
| Recording resilience | Abort handling and injected completion-write/flush tests | Dedicated bounded I/O execution, prolonged operation, physical fault/power-loss evidence; failed rollback can remain uncertain |
| Other Cortex capabilities | Individually scoped rows in `capability-matrix.json` | Contact classifications, gestures, performance targets, EDF and other hardware remain separately gated |

## Next implementation order

1. Extract one reusable analysis-window → feature → detector step from replay;
   test identical proposals for identical validated inputs, including invalid-window
   resets. Do not fork another feature recipe for live capture.
2. Add a bounded serial native shadow-processing consumer with explicit overload,
   disconnect and profile-change resets. Capture raw measurements independently of
   whether inference succeeds. Persist profile/configuration identity and rejection
   reasons; do not enable system actions.
3. Move blocking recording I/O out of UI/Bluetooth delivery while preserving order,
   abort semantics and evidence acknowledgements. Measure latency and queue bounds.
4. Qualify UI/audio and the exact headset configuration with fresh participant
   readiness. The most recent attempted UI observation found the Mac locked;
   historical readiness does not authorize a new physiological experiment.
5. Run the documented independent-session protocol and artifact/ordinary-activity
   challenges. Accept or reject the trained profile from measured evidence.
6. Expand the remaining capability-matrix rows one at a time, preserving these gates.

CI passed at `0a6750e` (run 34911644557). The `b0f6d90` run 34911834013 was still
in progress when inspected. Local `b0f6d90` validation recorded 93 passing tests
and three successful native builds; none establishes live physiological accuracy.

## Shared window processing implemented

`EEGWindowInference` now owns the sequential analysis-window → spectral features
→ detector step, and `EEGReplayInference` delegates to it. Rejected windows reset
detector state; malformed window structure rejects explicitly. Results retain
ordinal, reasons and experimental candidate and explicitly disable control.
Replay still validates the complete source and excludes exact training content
before releasing its report. The shared step itself does not assert held-out
status: that remains a host-level whole-recording check.

A native regression compares shared sequential processing with the replay report
on the same finalized synthetic recording, checks identity rejection and malformed
window handling. Existing numerical/detector tests remain in the suite. A bounded
live consumer and acquisition/UI integration are still required; extracting this
component does not mean live inference is running.

## Bounded live shadow consumer implemented

`EEGLiveInference` serializes metadata/sample input through the existing canonical
window assembler, sample validator and shared window processor. The default limit
is 512 pending inputs (including work in progress), configurable at construction.
Event payloads over the existing 4 MiB event limit reject during processing.
This is a count bound, not a total-byte memory budget. A false `submit` return
means no admission; overload increments the generation and queued older work is
discarded. Stop rejects future submissions. Reset, overload and malformed input
clear window/detector continuity, requiring fresh configuration/stability input.

Callbacks run on the worker queue. Hosts must check generation again on UI delivery
and keep raw recording independent of inference admission. No callback authorizes
an action. The callback can race a later reset, which is why generation accompanies
every result. The consumer does not drain a partial window into a fabricated result.

Tests compare its complete-window results with canonical replay on identical
synthetic samples, use a suspended worker to prove bounded admission and stale
queue rejection, and verify stop rejects further input. These are software tests,
not live headset evidence. Acquisition/profile UI integration and total-byte queue
budgeting remain unfinished; this component alone is not a running live workflow.

## Acquisition shadow integration

Acquisition now submits decoded samples to `EEGLiveInference` after recording
those measurements. `LiveShadowView` starts it explicitly for the inspected
profile, a declared participant and a non-training session ID. Active recording
and stable transport are required. Start metadata includes profile/feature IDs;
window candidates/reasons and stop causes are separate recording events with
system control explicitly disabled. Results are accepted on the main queue only
if both the consumer token and generation still match.

Loss of transport, overload, input rejection, recording failure, recording stop
or profile-view closure stops inference and clears the displayed candidate. No
restart occurs automatically. Samples continue recording if only inference stops.
The producer currently runs on the main queue and raw file I/O remains synchronous;
this is not a latency-qualified architecture yet. Window ordinals are relative to
the shadow run, not a global recording-window index. More precise per-window
source-range provenance remains to be added before offline/live alignment can be
qualified. Whole-content training reuse can only be checked after capture ends.

The core live/replay regression remains the current software evidence. This app
integration has not been exercised with a physical headset or interactive profile
controls, and no physiological accuracy or production readiness is claimed.

## Shadow source ranges

Shared window results now retain first/last source sample indices, sample count
and first/last receipt timestamps. Empty rejected windows have unavailable bounds.
The acquisition log records these as `first_sample_index`, `last_sample_index`,
`sample_count`, `input_start`, `input_end`, with `recorded_receipt_seconds` timing.
The separate `receivedAt` remains callback-delivery time. Start/result/stop records
share `shadow_run_id`; results also include reset generation. Thus a restarted
run's ordinal zero cannot be confused with the previous run's ordinal zero.

Regression assertions check the exact indices and timestamps of known synthetic
windows. Existing live/replay equality checks now include these fields. This
provides alignment metadata, not proof that live capture matches replay under
real transport/load. A full alignment audit and latency measurement remain due.

## Live queue payload budget

The shadow consumer now admits at most `maximumPendingInputs` inputs (default
512) and `maximumPendingEventBytes` event bytes (default 4 MiB), including the
currently processing input until delivery returns. Each event also retains the
4 MiB individual limit. Admission rejects oversized events before enqueueing;
subtraction-based capacity checks avoid integer overflow. Samples must have the
canonical 15 ADC words and exactly 14 channel values per present dictionary,
with the shared sample validator accepting their contents before enqueueing.
These bounds cover logical input payloads, not exact process RSS, allocator
capacity or caller-owned storage. The analysis window and model remain separate.

Budget rejection returns false and invalidates the generation, just like count
overload. The native host stops shadow inference visibly while raw recording
continues. Stale queued work releases its accounting when drained. Reset/stop do
not pretend queued memory has already been released. Limits are constructor
configuration; they are not yet exposed in application settings.

A suspended-worker test fills the byte budget below the count budget, verifies
rejection/generation invalidation, drains stale work, and verifies accounting
recovery and oversize rejection. This is deterministic offline evidence, not a
hardware throughput or memory benchmark.

## Application processing-limit settings

The profile's live inference panel now exposes persistent pending-input and
event-byte limits under Processing limits. Positive integer validation blocks
invalid values; fields lock during a run. Restore defaults returns 512 inputs
and 4,194,304 event bytes. Each `shadow_start` stores the selected limits, so
later analysis need not infer them from current preferences. Large values can
increase retained data and latency; no claim of an optimal hardware setting is
made. The per-event parser limit remains 4 MiB.

Startup admission rejection (for example, a byte budget too small for device
metadata) stops the candidate consumer and rejects inference startup without
aborting the raw recording. Actual recording-write failure retains the existing
storage-failure path. This corrects the former shared catch that incorrectly
classified initial queue rejection as a recording storage failure.

Native platform compilation verifies the view and call sites. Interactive
settings persistence, startup behavior under a physical stream and accessibility
remain unqualified until exercised in the application.
