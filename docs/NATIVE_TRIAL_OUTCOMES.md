# Native scored-trial accounting

`native-labeled-evaluation-3` adds explicit scored-trial observations to the native
Swift evaluation receipt and app. These are independent protocol definitions,
not recovered Cortex detection parameters. Raw acquisition, model training,
features, inference and system-control gates are unchanged.

For each already accepted manifest trial:

- `contained_candidate_windows` counts armed, usable windows with a task candidate
  whose full persistence evidence starts at or after the scored interval start
  and the recorded cue (when present). The window must end inside the interval.
- `contained_target_windows` additionally requires the candidate label to equal
  the declared trial label. A different task label is not target detection.
- `scored_target_detected` is whether this target count is nonzero for a cued task.
- `scored_neutral_false_positive` is whether any contained task candidate occurs
  in a cued neutral trial. Any task label is a false positive for that trial.
- Both Boolean observations are null for other conditions or missing cues.
  Diagnostic counts remain available without a cue but cannot earn scored credit.
- `eligible_seconds` sums armed usable window duration; `eligible_fraction`
  divides by the entire declared scored interval, retaining gaps in the denominator.
  Eligibility does not mean that the classifier produced a non-rejected prediction.

These are observations, not inferred mental states. A false Boolean means no
qualifying candidate was observed; it does not imply good coverage, correct
neutral classification, physiological validity or reliable performance. Inspect
coverage and rejected/unarmed/unobserved exposure alongside every outcome.

## Distinction from episode metrics

Existing episode-onset counts, carry-in detection and
`first_cue_associated_candidate_latency_seconds` are unchanged. Scored observations count
qualifying candidate windows, rather than newly rising episodes. The current
detector retains the start of its candidate streak as evidence provenance; the
scorer does not shorten or move that start to earn trial credit.
Evidence beginning before the scored interval never earns contained-candidate
credit, even if the latest window is inside it. Carry-in rate limitations remain.

The dataset loader rejects trials with no extracted windows rather than silently
removing them. This accounting covers only accepted trials that successfully load;
it does not quantify exclusion bias or replace the saved trial-review journal.

## Evidence and remaining work

`ActivationEpisodesTests` exercise wrong-target labels, pre-cue evidence, trial carry-ins, unusable/unarmed periods,
neutral false positives, missing cues and coverage including gaps. Serialization
tests verify explicit null outcomes and diagnostic counts. This is synthetic
software evidence, not physiological validation.

The Python reference evaluator is unchanged; new native fields are an explicit
native protocol extension, not a claim of Python/vendor parity. Whole-trial and
whole-session uncertainty, grouped permutation analysis, prospective session
qualification and artifact-controlled evidence are still outstanding. No output
control is enabled by any metric.

## Version 4: pooled and per-session trial summaries

`native-labeled-evaluation-4` retains the version-3 observations and adds
`trial_metrics` and `session_trial_metrics`. Both group cued trials by declared
class. Neutral means `cued_neutral`; non-neutral classes mean `cued_task` for that
specific label. Blink/jaw/head/ordinary-activity controls remain in the separate
condition-exposure reports, never silently relabeled as cued-neutral trials.

| Field | Definition |
| --- | --- |
| `declared_trials` | Accepted, successfully loaded trials for this class and cued condition |
| `scored_trials` | Trials with a recorded cue, including zero-eligible-exposure trials |
| `observed_trials` | Scored trials with target detection (task) or any contained task candidate (neutral false positive) |
| `no_candidate_observed_trials` | Scored minus observed; not proof of successful neutral classification |
| `unavailable_trials` | Declared minus scored; currently missing cue evidence |
| `trials_without_eligible_exposure` | Declared trials with zero armed usable duration, including missing-cue trials |
| `observation_fraction` | Observed divided by scored; null when scored is zero |
| `declared_seconds` | Sum of complete declared scored-interval durations, including gaps and missing cues |
| `eligible_seconds` | Sum of armed usable duration across those declared trials |
| `eligible_fraction` | Eligible divided by declared seconds; null for an absent class |

One trial with several candidate windows contributes at most one observed trial.
Missing-cue trials are reported as unavailable, rather than counted as known
negative outcomes. Zero-exposure trials with cues remain in the observation
fraction denominator; always inspect their explicit count and coverage. Missing
cue/exposure evidence cannot satisfy prospective qualification simply because the
remaining observation fraction is high.

Session summaries use the same function as pooled summaries. An absent class is
explicitly zero trials with null fractions. Reusing a trial ID in another session
does not merge the two trials. The app exposes both summaries and the JSON receipt
preserves them for independent review.

Validation: `TrialMetricTests` exercise whole-trial weighting, missing/all-missing
cues, zero eligible exposure, separate controls, absent classes and a pooled result
that hides a failed session. Receipt tests verify counts and explicit nulls.
The 18 selected trial/evaluation tests pass. No binomial confidence interval,
trial/session independence, significance test, grouped permutation result,
physiological performance or automatic qualification decision is implied.
