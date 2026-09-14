# Shadow evaluation contract

`processing.evaluation.summarize` measures read-only proposals from the same detector used
by replay. It does not unlock control or infer stress, attention or neural origin.

Dataset trials can declare `condition`: `cued_task`, `cued_neutral`, `ordinary_activity`,
`blink_control`, `jaw_control` or `head_movement_control`. All controls require label
`neutral`. Legacy trials default only to cued task/neutral, never ordinary activity.
Controls are evaluation-only; `evaluate --controls-only` permits a neutral-only evaluation
without manufacturing task examples to meet the full-evaluation class gates.

`shadow_enabled` is a Boolean, default true for evaluated intervals. False intervals are
passed as rejected input to reset detector persistence and are excluded from exposure.
`cue_completed_at`, when supplied, must be the observed playback completion in the same
host time basis, not a planned offset. Missing cue times leave cued latency unavailable.
Requested cues and participant reports remain declarations, not objective neural labels.

One episode starts on a persistent candidate's rising edge. Consecutive candidate windows
with the same label, session and continuity identity and at most0.05s arrival gap remain
one episode. Neutral, rejection, label changes, gaps or source/segment changes end it.
Evaluation adds no refractory period. Every candidate window and its arrival-span duration
remain counted so a long activation cannot disappear behind one onset.

Changing trial/condition alone does not create a new onset. A carried candidate is reported
separately, and the affected condition's onset rate is unavailable. Cued detection requires
a new episode whose complete persistence evidence begins after observed cue completion.
The reported latency is last-input-arrival minus cue completion; it is not physiological
onset, BLE latency or measured live application response time.

Eligible exposure includes valid, shadow-enabled input even when the classifier abstains.
Artifact/invalid input and unarmed input are reported separately. Time outside contained
sample windows, including packet gaps and uncovered trial ends, is unobserved and receives
no credit. Overlapping windows/trials and inconsistent metadata fail; an evaluation trial
with no contained windows fails rather than silently disappearing from the denominator.

For explicitly ordinary activity with nonzero eligible exposure and no carry-in activation,
onset count / eligible hours is reported. The one-sided95% upper bound is
`0.5 * chi2.ppf(0.95, 2*(count+1)) / hours`; zero events yields about2.996/hours, not zero.
The bound assumes a constant independent event rate. Clustering, small exposure and
nonrepresentative activities limit interpretation. It is not a participant-level interval
or psychological/clinical validation. Per-trial results remain available for review.

Synthetic tests cover persistent episodes, gaps, carry-in, missing/preceding cues,
condition separation, overlap rejection, zero exposure and exact exposure arithmetic.
No real mental-command or ordinary-activity performance result is established by these tests.
