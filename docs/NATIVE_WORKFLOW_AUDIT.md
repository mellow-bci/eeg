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
