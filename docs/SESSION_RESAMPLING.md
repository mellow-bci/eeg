# Exploratory whole-session resampling

This optional native analysis measures variation under resampling of the available
session counts. It is **not validated confidence coverage**, a significance test,
physiological accuracy evidence or a release gate. It does not retrain a profile,
change detector parameters or enable commands. It is off by default.

## Statistical boundary

Cluster resampling retains observations within a sampled cluster rather than
pretending they are independent observations. Here a cluster is a declared
acquisition session, and its observed-trial/scored-trial counts are always selected
together. This follows the general cluster-resampling approach discussed in the
[authors' R Journal article](https://journal.r-project.org/articles/RJ-2023-015/).
It assumes independent, exchangeable sessions for an inferential interpretation;
a manifest declaration does not establish those assumptions.

The percentile calculation takes a central fraction of the resampled statistics,
as described in the [SciPy bootstrap reference](https://docs.scipy.org/doc/scipy/reference/generated/scipy.stats.bootstrap.html).
We deliberately call the result an exploratory **range**, not a demonstrated
confidence interval: small session counts, nonstationarity, acquisition selection,
missing exposure and trial-review selection can invalidate inferential use. More
resamples only reduce Monte Carlo variation; they do not add biological evidence.
This is our implementation/design choice, not a recovered vendor algorithm.

## Exact implementation

`EEGSessionResampling`, algorithm `session-pairs-percentile-v1`:

1. For one cued class, sort session IDs and select sessions with declared trials.
   Artifact-control conditions remain in their separate exposure reports.
2. Reject invalid counts/options. Return `insufficient_sessions` for fewer than two
   represented sessions; two is a mathematical minimum, not a qualification rule.
3. Return `incomplete_cue_evidence` if any represented session has unavailable trials.
   Do not silently drop that session or impute its outcome. Trials with cues but zero
   usable exposure stay in the denominator and remain explicit in the main report.
4. Return `no_observed_session_variation` if all observed/scored fractions are equal.
   In particular, all-zero or all-one data do not receive a misleading zero-width range.
5. For each iteration draw S complete session pairs with replacement from S sessions.
   Compute sum(observed trials) / sum(scored trials), not the unweighted mean of rates.
   No window or individual trial is resampled. Whole-session pairs preserve within-session
   dependence in these counts; between-session dependence remains an assumption.
6. Generate indices with SplitMix64, starting from the recorded UInt64 seed; use
   rejection sampling before the bounded remainder. Sorting IDs makes dictionary
   iteration order irrelevant. Random draws are reproducible, not cryptographic.
7. Sort replicate statistics and interpolate quantiles at `(1-mass)/2` and
   `1-(1-mass)/2` using zero-based position `(N-1)*p` and linear interpolation.
   All-identical draws return `degenerate_resamples`. Otherwise status is
   `exploratory_only`, never passed/qualified.

Settings are explicit per evaluation: default 10,000 iterations, seed 0, central
mass 0.95. Users may change them in the app or CLI; there is no subscription cap or
silent work truncation. Iterations must be at least two and mass strictly between
zero and one. These validation bounds do not imply statistical adequacy. Work is
O(iterations × sessions) plus sorting; stored statistics are O(iterations). Large
settings consume more memory/time. Native evaluation provides cooperative cancellation
at session/window/resample boundaries; an active file operation may finish before
cancellation is observed. Cancelled work produces no new receipt.

## Use and provenance

In **Evaluate labeled sessions → Exploratory session resampling**, enable the
analysis and enter resamples, seed and central percentage before evaluation.
Results appear alongside per-session counts and coverage. Changing options clears
the previous displayed receipt, so new settings cannot be attached to old results.

CLI example (use actual paths):

```sh
swift run --package-path apple EEGEvaluate --manifest DATASET.json --profile PROFILE.json \
  --recordings RECORDING_DIRECTORY --resamples 10000 --resampling-seed 42 --central-mass 0.95
```

`eeg.native-evaluation.v1`, introduced in `native-labeled-evaluation-5` and retained
in version 6, stores
`session_resampling` per class with algorithm, status, sorted session IDs, options
and available bounds. Without opt-in this field is null. Unavailable results have
an explicit status and no bounds. Seeds are unsigned 64-bit integers; consumers
must preserve integer precision. The original manifest, profile and source hashes
remain necessary to reproduce the entire analysis. The Python runtime is not required.

## Verification and limits

Synthetic counts `(1/2, 2/8, 7/10, 18/20)` with seed 42 and 1,000 draws give a central
95% range `[0.3, 0.8714285714285714]`. Reproduce the separate Python/NumPy calculation:

```sh
python tools/check_session_resampling_oracle.py
swift test --package-path apple --filter SessionResamplingTests
```

Tests verify paired unequal-denominator arithmetic against that oracle, determinism,
linear quantile interpolation, missing/degenerate evidence, invalid settings/counts
and cooperative cancellation. Receipt tests verify optional inclusion and preserved
settings. These validate calculation behavior only. Prospective physiological data,
coverage properties, session independence, cue/control confounds and a defensible
qualification decision are still outstanding. Grouped permutation testing is not
implemented by this analysis.

Validation checkpoint: 17 selected native tests passed; macOS/iOS/visionOS builds
passed. The native CLI evaluated the existing four-recording synthetic fixture,
retained all 40 evaluation-window predictions and the requested seed/count, and
returned `incomplete_cue_evidence` for both classes. Four invalid CLI option sets
were rejected with exit 2 and no stdout before source access. The NumPy oracle
ran using NumPy 2.0.2. The macOS controls, export, option-change invalidation and
cancellation were subsequently exercised with synthetic recordings; see
[the UI qualification record](qualification/NATIVE_UI_WORKFLOW.md). This does
not qualify physiological performance or interaction on iOS/visionOS.
