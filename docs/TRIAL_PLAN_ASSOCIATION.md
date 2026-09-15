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

The primitive is not yet wired into the app/CLI evaluation receipt. The caller
must first join a source-pinned recovered plan to its completed/reviewed trials,
verify correct single-command candidate semantics, cue/exposure/compliance
eligibility and complete outcome accounting. A manually supplied Boolean map is
not that evidence. Do not label unavailable trials false or silently analyze a
selected subset. Additional sessions need an explicitly reviewed combination
rule; this implementation does not pool subjects or shuffle between sessions.
The end-to-end grouped analysis requirement is therefore still open.

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
builds succeeded. The capability table generator/check also passed. End-to-end
receipt integration and physiological qualification remain unimplemented.

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

Receipt/UI/CLI integration remains pending, including binding the evaluator's
actual source digest and profile classes to this adapter and reporting explicit
unavailable states. The earlier raw Boolean-map primitive is not itself a
qualified evaluation path. Quality-dependent exclusions, sequence effects,
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
