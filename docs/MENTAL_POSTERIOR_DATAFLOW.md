# Posterior arithmetic: bounded reference and independent numerical checks

2026-09-15. This inspects the previously captured arm64 body, not a running vendor
classifier. All 12 trace lengths and SHA256 hashes were rechecked against the
capture manifest. The posterior trace hash is
`7a6ecf6ac61bcbcb1d4103383f9b6b34f22ae89912b11a1430cf09cc6c8956c1`.
The installed binary was not contacted or reverified in this pass. No trained
assets or vendor runtime are added to the application.

Source: [posterior.txt](../evidence/mental-command-reference/posterior.txt),
`0x100b1f48c` through `0x100b1fad4`. The separately named helper starting at
`0x100b1fad8` is outside this routine and is not included in the interpretation.

## What the body narrows

| Instructions | Observation | Interpretation boundary |
| --- | --- | --- |
| `0x100b1f4ec` | Copies the supplied scalar `d0` into preserved `d8`. | Caller ownership is traced in MENTAL_CALLER_DATAFLOW; units, defaults and UI sensitivity mapping are unknown. |
| `0x100b1f564`–`0x100b1f578` | Checks a second column exists, loads the first matrix extent and data pointer, then advances by extent × 8 bytes. The failure path names `Mat::col(): index out of bounds`. | Consistent with selecting column 1 of the input matrix's double storage. Matrix element meaning is not established. |
| `0x100b1f588`–`0x100b1f618` | Initializes `d9` to positive infinity, visits paired values plus an odd tail, and retains a smaller value with floating comparisons/selections. | For finite input values this obtains the minimum of the selected column. NaN/infinity behavior is not qualified as a scientific input policy. |
| `0x100b1f624`–`0x100b1f6dc` | Reduces the first column of a working matrix using paired/vector accumulation and an odd tail. | Working entries originate through untraced helpers called at `0x100b1f534` and `0x100b1f560`. The shape-error branch names element-wise multiplication, but that alone does not prove the full helper formula. |
| `0x100b1f6e0`–`0x100b1f750` | Retains the working element count, requests an extent increased by one through helper `0x100b23b0c`, and checks the retained index is now in bounds. | Supports an appended slot on the successful path; allocation/helper internals remain outside the captured body. |
| `0x100b1f754`–`0x100b1f768` | Computes `d1 = d9 × d8`, combines this with the working-vector reduction in `d0`, then stores `d1` at the appended index. | The appended value is a scaled minimum, not an independently identified neutral Gaussian. |
| `0x100b1f76c`–`0x100b1f84c` | Selects aligned/unaligned and vector/scalar loops, dividing every working entry by the same `d0`. | No explicit zero/finite denominator guard is visible between denominator formation and these divisions. Upstream validation, runtime input ranges and downstream handling remain unknown. This is not proof of a live vendor failure. |

On the successful vector-shaped, finite-input path, let `w` denote the working
entries **after the untraced helper**, `m` the selected-column minimum and `s` the
supplied scalar. The observed normalization is consistent with:

```text
added = m * s
output = concatenate(w, [added]) / (sum(w) + added)
```

This is a bounded algebraic interpretation of the instructions, not a recovered
end-to-end posterior model. It leaves the construction of `w`, class ordering,
neutral identity, signs/ranges, priors and empty/degenerate input policy unresolved.
It does not establish calibrated probabilities or an exact sensitivity algorithm.
Do not substitute this expression into the independent production pipeline.

## Independent stack and falsifiable check

`apple/Sources/EEGCore/MentalScoring.swift` uses our declared one-diagonal-Gaussian
per-class recipe with equal priors. It computes log scores, subtracts their maximum,
then exponentiates and normalizes. It does not append the reference routine's
scaled-minimum entry. Model-space distance rejection is separate from relative
score normalization; neither mechanism establishes physiological validity.

The new analytic test uses a one-dimensional identity projection, means 0 and 1,
unit variance and a feature value of 50. Both ordinary densities round to zero in
Double arithmetic. Their mathematical likelihood ratio remains `exp(-49.5)`.
The test verifies this ratio within a relative tolerance of `1e-12`, finite
nonnegative normalized scores, and rejection by the detector over four adjacent
windows because the sample lies outside the declared distance limit. It checks
that candidate, evidence start and command remain absent and control remains off.
This rules out one specific failure mode: treating a dominant relative score on
this outlier as usable command evidence. It does not exhaust numerical inputs or
prove that all physiological artifacts are detectable in PCA space.

```sh
swift test --package-path apple --filter 'MentalScoringTests|ExperimentalDetectorTests'
```

Eight tests passed, including the existing Python-oracle transform/score cases,
invalid/extreme features and detector reset/persistence checks. No production
algorithm changed, and no new app build, hardware trial, latency qualification,
Cortex output comparison or physiological result is claimed by this pass.

## Native Gaussian coordinate-scale stability

A subsequent analytic check exposed an independent native numerical defect:
`delta * delta / variance` and `log(2π * variance)` formed intermediate products
that could overflow or lose precision despite a representable final result.
The new coordinate-scale test failed with `numericalFailure` before the change.
The native scorer now computes:

```text
standardized_i = (projected_i - mean_i) / sqrt(variance_i)
distance = sum(standardized_i²)
log_density = -0.5 * (distance + sum(log(2π) + log(variance_i)))
```

This is the same declared diagonal-Gaussian formula with more stable evaluation,
not a recovered vendor parameter or a new trained model. Finite checks remain;
genuinely unrepresentable transformations, distances or scores still reject.
This does not promise stable arithmetic for every conceivable input.

`MentalScoringTests.testGaussianCoordinateScaleDoesNotChangeDistanceOrRelativeScore`
checks variances 1, `1e308`, and four times Double's smallest positive subnormal.
Coordinates and means scale by the square root of each variance. The independent
analytic expectations remain squared distances 9 and 4, relative score
`exp(-2.5)`, and out-of-distribution rejection at distance limit 3. A separate
unequal-variance case checks normalized scores 1/3 and 2/3 at the common mean,
testing the determinant independently from distance. These are numerical kernels,
not evidence that such extreme parameters are fitted or qualified profiles.

The following 17 tests passed after the fix, including the existing Python-oracle
cases and the finalized live/replay recording comparison fixtures:

```sh
swift test --package-path apple --filter 'MentalScoringTests|ExperimentalDetectorTests|ShadowVerificationTests'
```

The Python research implementation and its historical fixtures were not changed;
this check establishes native behavior and ordinary-fixture agreement, not Python
equivalence at the new extremes. Native source identity changes with the scorer,
so historical shadow receipts still distinguish their recorded implementation
from the new one. Original recordings and fitted profile parameters are unchanged.

`./apple/build-native.sh all` passed for macOS, iOS Simulator and visionOS Simulator.
The independent source-identity oracle also passed. No application launch,
Bluetooth scan, headset capture or participant trial was performed for this fix.
