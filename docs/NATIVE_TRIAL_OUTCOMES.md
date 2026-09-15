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
