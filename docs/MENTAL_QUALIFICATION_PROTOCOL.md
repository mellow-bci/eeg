# Prospective qualification: silent serial subtraction versus neutral

Protocol: **`eeg.silent-subtraction-neutral.v1`**, proposed on 2026-09-15. No capture,
audio cue, participant request or hardware operation was performed to create this document.
This is a personal, independent task-condition experiment. It is not a diagnosis, cognitive
score, vendor mental-command reproduction or evidence of free-form thought reading.

## Named target and interpretation

The only task label is `silent_serial_subtraction`: silently subtract three repeatedly from
a supplied three-digit starting number for the trial period, without speaking or deliberately
moving the lips, eyes, jaw or head. The comparison label is `neutral`: remain comfortably
seated with eyes open, without deliberately doing the subtraction task. Natural blinking
is allowed. Both conditions use the same posture, lighting, display and recording setup.

This choice provides a concrete instructed activity. It does **not** establish that the
existing spectral classifier can distinguish it, that a difference is exclusively neural,
or that neutral means an objectively known mental state. The intended result is initially
“prediction of reported task condition under this protocol.” A stronger neural-intent claim
requires prospective artifact-controlled evidence and remains a separate decision.

## Readiness and stopping

Before each session, explain the entire sequence, obtain a fresh explicit ready response,
verify the participant heard an audio check and confirm that they can stop comfortably.
Do not start from a historical “ready” message. No flashing stimulus is used. All task
periods keep eyes open; a participant may pause or stop at any time.

Stop the trial immediately on participant request, discomfort, failed cue playback,
headset disconnection, loss of stable transport, unsupported configuration, disk failure
or a timing failure. Give an audible end instruction if playback remains available and
show the stopped state. A failed cue cannot be guaranteed audible: preserve that failure
and use visible status. Mark interrupted trials unusable and record the reason; never
emit a completed-trial event simply because the planned duration elapsed. Do not silently
restart after reconnection. Resume only with a new trial and an explicitly acknowledged
participant-ready state. A process crash cannot guarantee a final cue.

## Recording and label evidence

For each independent session retain the original immutable recording, participant
pseudonym, session ID, date, exact device/revision/configuration, software commit, feature
configuration, cue plan/seed, raw file hash and canonical ADC/counter content hash.
Reapply the headset between independent sessions and record that procedure. Renaming or
splitting one capture does not create independent acquisitions.

For every trial retain these distinct fields in an evidence sidecar:

- `requested_condition`, starting number and precommitted trial order.
- Cue playback request/start/completion, task-start/task-end timestamps and timing basis.
- `participant_report`: attempted task, stopped/uncertain/missed cue, and optional last
  remembered result, obtained after the scored interval.
- `observed_behavior`: visible speech/lip/jaw/head movement or blinks, with observer method
  and timestamps; unknown when no observer/reference sensor exists.
- `accepted`, exclusion reason, reviewer identity/time and links to the source evidence.
- Model predictions in a separate output; predictions must never alter ground-truth labels.

A correct reported final number may support that the task was attempted; it cannot prove
continuous compliance or neural origin. Self-report is not objective measurement of mental
state. An observer can annotate movement, not directly observe the calculation. Do not
activate a camera or additional sensor without explicit consent. If no independent
behavioral observation exists, document the limitation rather than marking movement absent.

The current dataset schema's `label_verified=true` is an **operator declaration**, not an
objective verification mechanism. Set it only after reviewing the cue/compliance evidence
under the declared task-condition policy; retain the evidence sidecar stating the limited
basis, such as `cue_acknowledged_and_participant_reported`. Never describe this flag as
“neural label verified.” Missed/uncertain cues stay rejected. If the intended label cannot
be supported even as reported task condition, it must not enter training or evaluation.

## Trial structure

Generate and save a balanced randomized order before recording, with at most three trials
of the same condition consecutively. Use a saved seed; do not select trials after looking
at EEG. Use different order seeds and starting numbers across sessions. Numbers are not
features supplied to the classifier.

1. Play a short instruction naming the condition and starting number. For neutral trials,
   also announce a number but explicitly ask the participant not to perform subtraction.
   This partially controls auditory input, not all cognitive effects of the cue.
2. Log actual playback completion, then begin a **20-second condition period**. The
   scored interval is from completion +5 seconds through completion +17 seconds, excluding
   the initial transition and final three seconds. Fixed exclusion helps avoid immediate
   cue transients but does not prove all auditory/anticipation effects have disappeared.
3. Play an end cue. Obtain the brief compliance report **outside** the scored interval.
   Report timing is retained and excluded from EEG classification windows.
4. Allow at least ten seconds of neutral rest after any spoken report. Pause for a
   one-minute optional break after every eight trials; additional breaks are allowed and
   recorded as boundaries.

Each acquisition targets **12 task and 12 neutral trials**. Expect roughly 15–20 minutes
including instructions, reports and breaks, but permit early stopping. The 12-second scored
interval ordinarily contains several complete two-second windows; count the actual valid
windows after extraction. Do not fabricate/pad windows to meet a minimum. If too few remain,
report insufficient data and schedule a new independent session only with fresh readiness.

Cue words and condition instructions remain potential confounds. The classifier receives
only signal features, never cue text, trial number, starting number or timing labels.
A later confirmation study should vary the instruction modality/timing and test whether
performance persists; initial success does not remove this confound.

## Session separation and frozen model

| Sessions | Purpose | Allowed use |
|---|---|---|
| A and B | Initial independent development acquisitions, preferably different days with headset reapplied | Training only. Fit all scaling, feature ranking, PCA and Gaussian parameters here. |
| C | Independent development/selection session | Evaluate failure modes and choose a final declared design. If used to tune anything, it is development data forever. |
| D, E and F | Prospective test sessions after the design/profile is frozen; different days where practical | Untouched reported-condition evaluation. Do not refit thresholds/transforms after seeing results. Report each session and pooled results separately. |
| Additional challenge sessions | Non-task blink/jaw/movement conditions | Artifact/nuisance testing under the frozen profile; no implicit addition to training. |
| Additional ordinary-activity sessions | No intentional subtraction task, realistic specified activities | Continuous shadow-mode false-activation exposure, separate from cued trials. |

This is an initial personal experiment, not sufficient population evidence. Thirty-six task
trials over D/E/F do not satisfy a separate 100-event pilot criterion and must not be
reported as such. If a failed test inspires a code/model change, version the change and
collect a new untouched future test; do not relabel D/E/F as still unseen. Cross-user claims
require other independent participants and an explicitly different evaluation design.

## Compatibility with the actual processing workflow

The current path is `processing.workflow`: explicit canonical adapters → nonoverlapping
256-sample windows → 70 spectral features → independent PCA/diagonal-Gaussian profile →
read-only proposals. Use the `eeg.dataset.v1` manifest with the named labels above and
monotonic trial boundaries. Only fully contained windows receive a label.

Current engineering requirements are neutral plus one or more task classes, at least 20 training
windows/class across at least two training sessions, accepted/verified-label declarations,
unique windows, one canonical recording hash/session and different hashes across sessions.
Evaluation requires at least ten windows/class and rejects training/evaluation ID/content
overlap. These minimum counts prevent trivial inputs; they do **not** establish statistical
power, physiological sufficiency or independence of windows inside a trial.

The manifest accepts only `train` and `evaluation` splits. Use C in a separate development
manifest and never include it in final reported D/E/F results. Freeze the profile ID, source
commit, feature configuration, selected windows, score/rejection/persistence parameters and
analysis plan before D. The implementation has no automatic “approved model” promotion.

Reject scored windows with transport/configuration problems, epoch/segment boundaries,
missing calibration, invalid values, current artifact flags or partial windows. Preserve
all exclusions and unavailable time. Current amplitude/flat thresholds are unvalidated
engineering rules: passing them does not establish artifact-free EEG. Do not discard a
valid window solely because its prediction is wrong. Artifact-marked evaluation data must
remain visible as rejected/unavailable outcomes rather than inflating accuracy by omission.

## Separate nuisance challenge blocks

Run only after renewed explanation/readiness, with the frozen profile and no external
outputs. The participant does **not** perform subtraction during these blocks. Use six
observed events per condition as a first feasibility screen, with at least ten seconds
between events and rest/breaks as needed:

- Deliberate single/double blinks, plus spontaneous blinks during rest.
- Gentle brief jaw movement or a normal short spoken phrase; no forceful clenching.
- Comfortable small head turns and ordinary posture adjustment; no strenuous movement.
- Neutral speech cues without a subsequent instructed calculation.

Record actual behavior separately from cue times where possible. Do not count an unobserved
prompt as a completed artifact event. Score every detector crossing, rejection, candidate
and recovery relative to the annotated event. A task candidate during a non-task challenge
is a false positive for this protocol, not successful mental control. A small challenge
screen with zero false positives is not a low false-activation-rate estimate.

Use `workflow evaluate --controls-only` for separately labeled neutral challenge or ordinary-activity recordings. Do not add dummy task trials. Declare `condition` explicitly as `blink_control`, `jaw_control`, `head_movement_control` or `ordinary_activity`; additional control types need a versioned extension rather than being mislabeled. Full task evaluation retains its per-class sample gates.

## Ordinary-activity exposure and event accounting

With explicit consent, record separate no-intended-task blocks while the detector runs in
**shadow mode**: quiet sitting, reading, ordinary conversation, natural blinking and posture
adjustments, each identified separately. Allow breaks. Never infer absence of intent solely
from the classifier's output; record the no-task instruction and participant report while
acknowledging their limits. These conditions support only their named exposure claims.

First collect enough valid armed exposure to characterize behavior, then extend toward the
predeclared target. Proposed exploratory local-pilot target: one-sided 95% upper false-event
rate below 1/hour. With zero events, a constant-rate Poisson model gives an upper bound
`2.996 / valid_armed_hours`; approximately three zero-event hours only just meet that target
under its assumptions. It does not establish the more demanding 0.1/hour target, which
would require roughly 30 zero-event hours under the same assumptions. Split exposure over
representative days/activities and report clustering/nonstationarity; this is an engineering
criterion, not medical safety certification.

Freeze event accounting before analysis: a false activation starts when an eligible
experimental task candidate first appears; consecutive candidate windows belong to the
same episode until at least one noncandidate window. Also report every candidate window,
episode duration and rejected/unavailable time so long episodes are not hidden by counting
once. Any different debounce/event definition requires a new declared analysis version.
Do not count detector-disabled or unusable periods as valid armed exposure. Report gross
wall time, valid armed time, rejected time and gaps independently.

The shadow evaluator now reports episode onsets, candidate-window duration, eligible/rejected/unarmed/unobserved exposure and a conditional one-sided Poisson upper bound. Carry-in activity is reported and leaves onset rates unavailable. These are software-tested calculations; no real ordinary-activity rate has been validated. See [SHADOW_EVALUATION.md](SHADOW_EVALUATION.md).

## Evaluation decisions and reporting

Before opening prospective results, freeze per-trial scoring: a task trial is detected if
at least one persisted experimental task candidate occurs wholly inside its scored interval;
a neutral trial is a false-positive trial if one occurs there. Report window-level outcomes
as supplementary information, not independent trial counts. Include per-session task
sensitivity, neutral false-positive fraction, abstention/coverage and time-to-first-candidate.
Processing-call latency excludes BLE, cue timing and human response. The model's two-window
persistence already requires roughly four seconds of accumulated signal.

For this first feasibility screen, predeclare exploratory engineering targets of at least
80% task-trial detection, at most 10% neutral false-positive trials, and at least 80% scored
window availability, reported separately for D/E/F as well as pooled. These are proposed
screening targets, not validated clinical or scientific thresholds. Compare with an
always-neutral baseline and a label-permutation analysis grouped by whole trials/session;
never permute correlated individual samples. Report trial/session uncertainty and the
limitations of only three test sessions. Passing point estimates alone does not satisfy
ordinary-activity exposure, artifact-control or neural-origin claims. The current CLI does
not calculate these trial-level uncertainty/permutation results; retain predictions for
a separate reviewed analysis rather than inventing them.

There is **no automatic pass to neural origin or output control**. Outcomes are:

- **Insufficient evidence:** inadequate accepted trials/exposure, uncertain compliance,
  unsupported acquisition or protocol deviations. Preserve the data and reasons.
- **Task-condition discrimination candidate:** prospective results exceed a frozen
  baseline under the named conditions, with uncertainty and nuisance failures reported.
  This remains an experimental personal model.
- **Rejected design:** failed declared performance/exposure gate, substantial nuisance
  activation, unreliable quality/coverage or invalid independence. Revise only in development,
  then obtain a new held-out session.

No fixed software window minimum or self-report can prove neural causation. Evidence needs
independent artifact observations/controls and repeatability across changed cue conditions;
stronger claims require an appropriately designed scientific study beyond this initial plan.
Use [COGNITIVE_VALIDATION.md](COGNITIVE_VALIDATION.md) and
[MENTAL_WORKFLOW.md](MENTAL_WORKFLOW.md) for the broader limitations and actual software.

Throughout this protocol `command=null`, `system_control_enabled=false` and the explicit
experimental status remain unchanged. No score, completed trial or favorable report can
automatically enable Apple HID, Cast, application automation or any system-wide action.

## Native evidence state machine

`apple/Sources/EEGCore/TrialEvidence.swift` implements the trial evidence sequence
as `EEGTrialEvidence` (`eeg.trial-evidence.v1`). It is an independent protocol
implementation, not a vendor algorithm. It does not play cues or start acquisition.

Transitions separate cue request, actual playback start/completion, the condition
period, end-cue request/start/completion, participant report and operator review.
The controller must supply recording-clock timestamps from actual callbacks; a
scheduled playback time must not be substituted for playback completion. Times
must be finite, nonnegative and nondecreasing. Starting requires explicit readiness,
heard audio-check, stable transport and active-recording assertions. These inputs
are controller assertions, not independent measurements by this state machine.

Only an explicitly accepted operator review of an `attempted` report can emit an
`eeg.dataset.v1` trial row. The emitted interval is cue completion +5 through +17
seconds; the end cue cannot be requested before +20 seconds. `uncertain`,
`notAttempted` and `missedCue` reports cannot be accepted. Interrupted trials retain
an event/reason and cannot resume or emit labels. Reviewed records are terminal;
a correction must be recorded separately rather than mutating the completed trial.
Unknown behavioral observation remains `unknown`, including for an accepted
reported-task label. The evidence sidecar must be retained with the dataset.

Remaining controller duties: persist events durably, bind recording identity/clock,
connect actual audio callbacks, detect playback/timing/transport failures and call
interrupt, implement pause/stop, precommit balanced trial order, collect review in
the UI, and preserve a reproducibility bundle. There is no automatic late-cue
tolerance or evidence of precise playback timing here: the controller must treat
its detected timing failures as interruptions. No live experiment has exercised
this state machine yet. Unit tests verify explicit review, scored intervals,
readiness/sequence/time rejection, interrupted trials and missed-cue exclusion.
