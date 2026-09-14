# Cognitive metrics, HCI gestures and neural intent: validation plan

Checkpoint 2026-09-15. This document defines proposed acceptance gates; it does not report
those gates as achieved. No hardware capture or participant experiment was started while
writing it. Apple HID, Cast actions and other external outputs remain disabled.

## Three different capabilities

| Track | What it may claim after validation | What it must not imply | Primary evidence |
|---|---|---|---|
| Descriptive EEG analysis | Measured band power, spectrum, signal variability and repeatable task-associated differences under stated conditions | A stress, attention, engagement or emotion score merely because a vendor uses that label | Defined signal processing, units, repeatability, artifact controls, uncertainty and independent task measures where relevant |
| Intentional HCI gesture | A deliberately performed, individually calibrated blink/gesture can operate a local test control | Detection of a thought or a neural command; ordinary spontaneous blinks may be indistinguishable without additional intentional interaction design | Event-level gesture ground truth, neutral false activations, latency and error recovery |
| Neural intent classifier | Performance on a precisely named trained task for a defined participant/session population | Free-form thought reading, untrained goals or general cognitive understanding | Task labels independent of predictions, separated training/testing, artifact controls and prospective held-out sessions |

A fourth possibility is a hybrid input combining EEG, a switch, gaze, voice or a gesture.
Label the modality honestly and measure the contribution of each input. A high-scoring
ocular classifier is useful HCI but cannot be renamed a neural intent classifier.

## What the archive actually contains

Source inspection: `research/audible_eye_test.py`, `research/analyze_blinks.py`,
`research/compare_eye_phases.py`, and the sidecars in `archive/current-state/`.

| Artifact | Actual labels / interpretation |
|---|---|
| `live-audible-direct-20260914T184711Z.markers.jsonl` | Six markers: eyes_open_1, eyes_closed_1, eyes_open_2, eyes_closed_2, eyes_open_3, test_complete. Timing is local speech-process completion. Every marker sets participant_compliance_verified=false. |
| `live-blinks-discovery-20260914T185827Z.markers.jsonl` | Nine markers: baseline, blink_1 through blink_6, rest, test_complete. Same timing basis and unverified compliance. |
| `live-controlled-20260914T183707Z.markers.jsonl` | Four operator markers: open, closed, open, complete, near the latest notification. These are not measured eyelid transitions. |
| `live-audible-eyes-20260914T184620Z.markers.jsonl` and `live-blinks-20260914T185733Z.markers.jsonl` | Empty. Do not turn an empty or aborted protocol into labeled trials. |
| Historical blink analysis | Four-second pre/post cue RMS comparisons; six larger frontal responses. No independently measured blink times, sham cue control or trained classifier. |
| Historical eye analysis | Posterior alpha response was inconsistent; outcome inconclusive. It cannot serve as a validated eye-state or cognitive model. |

The original eye schedule was 20/30/20/30/20 seconds; spoken cue time was additional. The
blink schedule used six double-blink cues, not six independently annotated successful
double blinks. Preserve those distinctions in imports and evaluation reports. See
[SIGNAL_EXPERIMENTS.md](SIGNAL_EXPERIMENTS.md) for exact processing and observed ratios.

## First new experiment: local observation only

Protocol identifier: `eeg-observation-audio-v1` (proposed; not implemented by this document).
Use steady illumination, no flashing stimuli and no external actions. Estimated duration
8–12 minutes with optional breaks. Natural blinking is allowed during neutral periods;
forcing suppression would make false-activation testing unrepresentative.

1. **Participant readiness:** explain the sequence, obtain an explicit current “ready,”
   confirm audio is audible, sensors prepared and that the participant can stop at any time.
   Historical consent or “wearing it” messages do not establish readiness for this new run.
2. **Transport preflight:** identify exact device/configuration, require stable calibrated
   delivery, start a new session/protocol ID, and verify recording and cue playback. An
   interruption aborts the trial and asks the participant to open their eyes; it never
   fabricates a completed trial.
3. **Neutral baseline:** 120 seconds of ordinary quiet sitting with eyes open. Record
   spontaneous movements rather than relabeling them as intended commands.
4. **Eye observation block:** four eyes-open and four eyes-closed periods, each 20 seconds.
   Use a predetermined balanced order that is stored before capture; finish with an explicit
   open-eyes cue. Announce every transition and preserve playback start/end timestamps.
   This explores repeatability, not cognition. Discard a predetermined 5 seconds after
   playback completion and 3 seconds before the next cue from spectral comparison.
5. **Rest:** 60 seconds, optional participant-requested pause. A pause creates a boundary.
6. **Gesture-control block:** 12 randomized trials, six deliberate double-blink and six
   neutral “continue resting” cues, separated by 12–18 seconds according to a stored seed.
   The classifier does not receive the cue/trial type. Score an event in the predetermined
   0–4 second post-playback interval; also measure inter-trial false activations. This
   small block is only a feasibility experiment, not sufficient training/validation.
7. **Neutral ending:** 120 seconds with no intended commands, then an audible completion
   cue. Ask for compliance notes or missed cues after recording; do not silently overwrite
   cue labels with assumed compliance.

Ground truth must distinguish `cue_requested_action`, `observed_action`, and
`participant_report`. An observer timestamp or separately consented synchronized video/EOG
may establish actual blinks; do not enable camera recording without explicit consent. If
only cues exist, report **cue-associated responses**, not true gesture sensitivity.
Audio cues can themselves produce responses: include neutral speech cues and never train
using marker names, cue text, absolute phase time or trial order as predictive features.

## Data and split contract

Every trial must retain participant pseudonym, session ID, protocol version, trial ID,
monotonic cue times, observation method, valid sample interval, epoch/stable segment,
excluded intervals/reasons and raw recording SHA-256. Store acquisition and feature
configuration versions with the model artifact. Unknown labels stay unknown.

Split **before** feature normalization, imputation, channel selection, feature selection,
artifact-model fitting or hyperparameter tuning. Fit these steps on training data only.
All overlapping windows from one trial stay together; all trials from a held-out session
stay held out. Do not randomly split adjacent windows from one recording and claim
independent test performance. Subject-independent claims additionally require participants
absent from training and model selection. Leakage can substantially inflate EEG evaluation;
this is demonstrated by primary research comparing segment and subject holdouts.
[Data leakage in deep learning studies of translational EEG](https://pmc.ncbi.nlm.nih.gov/articles/PMC11099244/)

Initial personal-model design: session A for training, B for threshold/model selection,
and C on a later day, with headset reapplied, for an untouched prospective test. Three
sessions are a starting design, not enough to quantify all between-day variability.
If test results lead to tuning, C becomes development data and a new future session is
required. Repeated trials increase within-session evidence, not the number of independent
sessions. Report both counts.

For real-time claims, evaluate causal processing with exactly the allowed look-back and
latency. Offline zero-phase filters or future-window information cannot be credited as
online performance. Rejected/low-quality windows count toward unavailable time and coverage;
exclude them only under predeclared rules, never because they produced incorrect results.

## Proposed gates, in order

| Gate | Required measurement / decision |
|---|---|
| G0: acquisition | Independent transport qualification, supported scaling, no unreported gaps, explicit quality limitations. Raw Cortex equivalence is separate evidence and is not a classifier test. |
| G1: descriptive analysis | Reproduce feature calculations on fixed reference arrays; report PSD units/window/filter/band definitions. For an eye-associated effect, show per-trial O1/O2 changes across sessions and uncertainty rather than choosing a favorable channel afterward. Inconclusive results stay inconclusive. |
| G2: gesture feasibility | Independently annotated intended gestures and sham/neutral controls; event matching with a frozen time window and one-to-one assignment. Extra detections count as false activations. Report misses, latency distribution and unavailable time. No system output. |
| G3: personal local-control candidate | Proposed target: at least 100 held-out intended events across at least 3 test sessions, at least 95% event sensitivity, and report the binomial interval rather than claiming certainty. Threshold and refractory period frozen beforehand. Additional neutral requirement below. These are engineering targets, not a clinical standard. |
| G4: neural-task candidate | Name the task and population first. Compare with majority/random baselines using trial/session grouping. Include ocular/muscle control conditions; demonstrate the result cannot be explained solely by gestures, cue timing or data leakage. Report a confusion matrix, abstention coverage, per-session variability and latency. No universal accuracy threshold can establish physiological origin. |
| G5: limited output pilot | Only after prospective gates and deliberate user enablement: one reversible local test action, neutral/armed distinction, expiry, debouncing, confirmation, cancel and kill switch. Apple HID/Cast adapters remain disabled until their own integration tests pass. |
| G6: broader capability | Repeat after headset reapplication, different days and representative activities. A multi-user claim requires independent people and their results. Any cognitive construct needs its own protocol, independent reference measure and validated interpretation; do not inherit EMOTIV's score names or proprietary meaning. |

Intervals should respect the experimental unit: trial bootstrap for event metrics within a
session, session-level resampling for cross-session claims when enough sessions exist.
Report small-sample limitations. Permutation tests must permute at the trial/session level,
not individual highly correlated samples. Publish exclusions and all planned outcomes.

## Neutral false-activation requirement and uncertainty

Evaluate the **armed detector in shadow mode**, continuously, without allowing actions.
A detector disabled for most of the test cannot claim that time as successful neutral
exposure. Include ordinary spontaneous blinks, posture changes, conversation and rest in
separately labeled blocks, plus a declared quiet-neutral subset. Do not reinterpret false
commands as intentions after seeing a prediction.

Proposed local-pilot target: a one-sided 95% upper rate bound below **1 false activation/hour**.
With zero observed events, a simple constant-rate Poisson assumption gives an upper bound
`-ln(0.05)/T ≈ 2.996/T` per hour. Thus 3 hours with zero events only just supports that
bound; 10 minutes with zero events does not. A more demanding target below 0.1/hour needs
roughly 30 zero-event hours under the same assumption, distributed over representative
sessions. These targets are proposed engineering choices and do not establish medical
safety. Correlated events and changing conditions weaken the constant-rate assumption;
report session-level results and do not hide clustered failures behind a pooled number.

For nonzero events use a declared exact Poisson interval or a justified alternative, and
report numerator, armed valid hours, unavailable hours and exclusions. Freeze debounce and
refractory duration before testing; log raw detector crossings as well as emitted commands
so a long refractory period cannot conceal instability. Exposure for quiet sitting does
not support a claim for walking, speaking or daily life.

## Output boundary

No EEG sample, band-power excursion or unvalidated confidence score may directly execute
system-wide actions. The chain is: validated input interpretation → explicit action policy
→ local preview/confirmation → separately tested output adapter. On stale input, loss of
quality, reconnect, app suspension or expired command, return to neutral and release any
held input. Apple signal feedback must not convert raw contact values into invented intent
confidence. This document creates no acquisition command, background capture or HID output.
