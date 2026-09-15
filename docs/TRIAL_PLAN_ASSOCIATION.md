# Conditional association under the native trial schedule

## What actual code establishes

`EEGTrialPlan` v1 generates 24 trials: twelve neutral and twelve silent serial
subtraction. It rejects an order containing four consecutive identical conditions.
The maximum run is now a shared constant, `maximumConditionRun = 3`; generation,
seed recovery, trial IDs, starting numbers and rest policy are unchanged.

Consequently an unrestricted balanced-label shuffle is not the v1 assignment
space. A plain fixed-margin hypergeometric/Fisher calculation also omits this
order constraint. The [SciPy Fisher documentation](https://docs.scipy.org/doc/scipy/reference/generated/scipy.stats.fisher_exact.html)
explains that fixed-margin reference distribution; it is a statistical reference,
not a vendor algorithm or evidence that this experiment meets its assumptions.

## Implemented calculation

`EEGTrialPlanAssociation.run(plan:candidateObserved:)` accepts the existing native
plan type and exactly one Boolean outcome keyed by every planned trial ID.
The outcome means that a candidate was observed in that trial's scored interval.
It is not a window-level label or a claim of successful mental control. Missing,
extra or substituted IDs are rejected. Artifact-control plans are unsupported.
The API does not infer an outcome for missing/rejected evidence.

The statistic is the number of candidate-observed trials assigned to the task
condition. Candidate outcomes remain at their original trial positions; each
entire trial is the unit of reassignment. The calculation counts all schedules
with twelve task assignments, twelve neutral assignments and maximum run three.
It never permutes EEG samples, windows, source recordings or participant IDs.

A dynamic-programming state contains task assignments used, last assigned label,
current run length and statistic value. Each next position admits neutral/task
only when both balance and run constraints remain satisfiable. Integer counts
are accumulated by final statistic. There are **705,982** admissible schedules.
At 24 trials even the unrestricted count C(24,12) is below UInt64 capacity.
The implementation checks cancellation between positions; it has no random seed
or iteration setting of its own, approximation, truncation or subscription cap.
This fixed length is the supported protocol, not a product tier.

The result preserves algorithm version, plan seed, ordered trial IDs, the fixed
outcomes, observed statistic, full integer count vector, total schedule count
and upper-tail count including ties. `conditionalUpperTail` is the latter divided
by the former. Integer counts, rather than a rounded display value, are the
reproducible result. JSON roundtrip retains the counts and reconstructs the ratio.
All results say `conditional_only_exchangeability_unverified`.

## What is deliberately not established

This is an exact count of the stated combinatorial reference space, **not an
exact probability of the finite PRNG's seed distribution**, and not a calibrated
significance or clinical decision. Its inferential use would require an appropriate
assignment/exchangeability argument. A fixed prospective seed is not evidence
that the participant's conditions were randomly assigned independently of their
signals, or that outcomes would remain fixed under reassignment.

Fatigue, task carryover, different cue audio, starting numbers, period/break effects,
quality-dependent rejection and prior tuning can undermine that argument. A small
conditional tail does not demonstrate neural origin, cognitive meaning, absence
of muscle/eye artifacts or superiority over Cortex. The held-out profile and
ordinary-activity/control requirements remain in force.

The app/CLI can now request this calculation through the canonical evaluator,
using the source and trial eligibility adapter described below. The current
implementation is per-session only. No between-session combination rule or
inference about independent sessions is implemented. The mathematical primitive
alone does not establish any of these additional conditions.

## Reproduction and software evidence

Run from the `eeg` repository:

```
swift test --package-path apple --filter 'TrialPlanAssociationTests|TrialPlanTests'
python3 tools/check_trial_plan_association.py
./apple/build-native.sh all
```

The native tests compare every possible outcome vector for lengths 2 through 8
and run limits 1/2/3 against an independent complete-bitmask enumerator. A second
Python enumerator checks all C(24,12) assignments using bitwise four-run rejection.
For candidate outcomes at positions 1–12 its count vector is:

```
[0, 0, 0, 380, 21281, 169490, 323680, 169490, 21281, 380, 0, 0, 0]
```

Tests additionally cover exact ID matching, ordering independent of dictionary
insertion, all-false/all-true ties, perfect/reversed synthetic association,
unsupported control plans, JSON roundtrip and cancellation. These are synthetic
algorithm checks; no headset, audio cues, vendor runtime or participant experiment
is used. No existing profile, prediction, evaluation version or raw sample changes.

Validation checkpoint, 2026-09-15: nine selected native tests passed; the Python
24-trial enumeration matched the count vector and total; macOS, iOS and visionOS
builds succeeded. The capability table generator/check also passed. This initial checkpoint preceded receipt integration; physiological qualification
remains unimplemented.

## Source and trial eligibility adapter

The internal `run(recording:store:expectedFileSHA256:participantID:sessionID:classes:trials:minimumEligibleFraction:)`
overload now joins a finalized recording's recovered plan/revisions to canonical
`EEGTrialTiming` outputs. `TrialRecordingEvidence` retains the plan already
validated during stream recovery. No second plan parser or trial state machine
is introduced.

The adapter requires:

- An exact recording digest match to the evaluator's expected source; matching
  participant/session identities; the binary neutral/silent-subtraction classes.
- All 24 planned trials started, reviewed, accepted and self-reported attempted.
  Missing, rejected or unreviewed trials prevent a result for the entire plan.
- Exactly those 24 distinct IDs in the trial summaries, all in the same session.
- Identical recorded labels, conditions, scored intervals and cue completion
  times to those produced by `datasetTrial()` from recovered evidence.
- Finite, nonnegative coverage and eligible exposure, eligible no greater than
  covered, and covered no greater than the declared interval. A relative 1e-12
  tolerance permits summation roundoff, not missing samples. Counts must be
  nonnegative and consistent with a single non-neutral command.
- Every trial meets an explicit caller-selected eligible fraction in (0,1].
  This adapter supplies no default and makes no universal validity claim for
  the selected threshold. Its value and all per-trial fractions accompany the
  source hash and conditional association result.

All checks finish before comparison. The adapter never drops trials, imputes
missing outcomes or rewrites samples. It is internal because its timing/count
inputs must come from the canonical evaluator; a hand-constructed summary does
not establish that the detector produced those outcomes. File hashes identify
bytes, not authorship or physical truth. Self-reported attempted and operator
accepted remain declarations, not independently verified compliance.

Receipt/UI/CLI integration now binds actual evaluator outputs to this adapter,
as described below. Quality-dependent exclusions, sequence effects,
exchangeability and physiological validation remain unresolved.

`TrialAssociationEvidenceTests` construct complete synthetic journals with every
transition and rest interval, then join synthetic timing summaries. They check
source/identity/class mismatches, missing/rejected/duplicate trials, absent cues,
invalid/insufficient exposure, count inconsistencies, result provenance and
unchanged source bytes. These fixtures deliberately contain no EEG: they test
the join and rejection rules, not detector performance or end-to-end capture.

Source-adapter validation, 2026-09-15: 17 selected native association, recovery and
dataset-export tests passed with zero failures. macOS, iOS and visionOS builds
succeeded. No headset or physical trial was used.

## Canonical evaluator, receipt, CLI and app integration

`EEGEvaluationArtifact.run` now accepts optional
`trialAssociationMinimumEligibleFraction`. Omission keeps comparison disabled.
A supplied fraction must be finite, greater than zero and at most one, validated
before dataset loading. The validated dataset's session summary retains its
recording filename and exact file digest. After canonical inference, each
evaluation session joins its actual trial summaries and profile class set to the
recovered source. Training sessions are not tested; inference is not rerun or
modified by enabling the comparison.

Receipt algorithm `native-labeled-evaluation-12` adds `trial_association`: null
when disabled, otherwise a dictionary keyed by evaluation session ID. Each entry
includes the requested exposure fraction and expected source digest. Eligible
sessions contain the complete source/result/count evidence. Ineligible sessions
have `status: unavailable`, a reason, and **no result field or probability**.
Reasons distinguish missing native plans, unsupported classes, incomplete reviewed
plans, timing mismatches and invalid/insufficient exposure. Source mismatches,
malformed journals, I/O failure and cancellation propagate as evaluation failures;
no partial new receipt is published. A missing-plan error carries the scanned
file digest so absence cannot hide a changed source.

The streams are checked at read boundaries, not held as immutable snapshots.
No guarantee is made against changes after reads or source forgery. This
integration verifies data linkage, not source authenticity, real cue audibility,
truthful compliance or absence of artifacts.

CLI example, with your local paths:

```
EEGEvaluate --manifest DATASET.json --profile PROFILE.json --recordings RECORDINGS \
  --trial-association-minimum-eligible-fraction 0.8
```

Invalid fractions exit 2 before evaluation and emit no receipt. A valid request
may return unavailable comparison entries while retaining the ordinary evaluation.
Source or evaluation failures exit 1 with no provisional receipt.

The app's labeled evaluation view exposes an optional **Conditional trial-schedule
comparison** disclosure. Its percentage field is editable while idle, defaults
to the protocol's proposed 80% engineering screen, and is frozen during evaluation.
Changing the toggle or percentage invalidates an earlier displayed/exportable
receipt. Results show per-session exact tail/total counts or a readable reason
for unavailability, with the conditional interpretation stated explicitly. No
significance coloring or automatic control decision is introduced. Freeze the
threshold before prospective results; the default is not physiological validation.

A synthetic end-to-end test writes all 24 trial journals and 36,864 EEG samples,
exports the canonical dataset, trains a separate synthetic profile, and runs the
actual evaluator both with and without comparison. Predictions must match; the
comparison must account for all 24 trials. A 100% exposure requirement returns
unavailable because window endpoints do not cover every instant. Separate tests
check missing-plan versus source-mismatch handling and malformed journals. The
CLI check exercises disabled and unavailable outcomes and invalid fraction inputs.
These are software tests, not headset qualification. Focused macOS QA now covers the controls, disabled-while-running state,
unavailable results, byte-identical UI/CLI export and percentage-change result
invalidation; see [NATIVE_UI_WORKFLOW.md](qualification/NATIVE_UI_WORKFLOW.md).
The follow-up complete-plan synthetic pass also covers eligible-result display,
byte-identical canonical/UI/CLI output and checkbox-change invalidation. Other
failure cases and iOS/visionOS interaction remain pending. Reproduction commands
and exact scope are in the linked qualification document.

Integration validation, 2026-09-15: the initial 22-test evaluation/recovery/export
selection passed; the five-test evidence suite including the complete synthetic
recording-to-receipt test passed; the final seven-test failure-path/analysis-window
selection passed after adding explicit recording-error equality conformance.
The native CLI checker passed disabled/unavailable comparison, unchanged prediction
and invalid-setting checks. Final macOS, iOS and visionOS builds all succeeded.
These selections overlap and are not a new full-suite or hardware qualification.
