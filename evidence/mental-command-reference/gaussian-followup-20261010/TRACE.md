# Gaussian, learned-transform and posterior follow-up — 2026-10-10

Reference: installed M4 CortexService arm64, expected SHA256
`cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`.
Static LLDB target/disassembly only: no process launch, attach, user-profile read,
weight extraction, licensing modification or vendor binary incorporation.

## Confirmed bounded arithmetic

### Learned PCA and canonical transforms

`pcaTransform` at `0x100b1e9cc` calls helper `0x100b20928` with the
mutable feature matrix and supplied mean, then helper `0x100b22ea8`
with the centered feature matrix and supplied basis.

The first helper checks identical matrix dimensions (`0x100b2093c..94c`)
and subtracts corresponding values (`0x100b209b0..9bc`, scalar tail
`0x100b20ae0`). The second checks left columns equal right rows
(`0x100b22ec4..ed8`), sizes output to left rows/right columns, and uses
ordinary matrix multiplication (`wrapper_cblas_dgemm`, `0x100b230a4`).
Thus for one feature row: `y = (x - mean) B`.

`canonicalTransform` at `0x100b1ec80` similarly centers with its own
supplied mean. If its unsigned K argument is >= 2 it selects basis
columns 0 through K-2 inclusive (`0x100b1ecfc..ed24`) before multiplication;
otherwise it uses the entire basis. Our API rejects K=0 rather than
assigning application meaning to that case. Neither body trains a basis.

### Full covariance Gaussian

`MvnpdfTxf::init(arma::Mat, arma::Mat)` at `0x10213f40c` checks dimensions
and stores mean/covariance. It calls `0x100b560bc` to factor covariance,
then `0x102140620` to invert the factor. The former calls `0x100b56260`
with mode 0 (zeroed expression mode at `0x10213f5d8`); its general path
selects ASCII U (`0x100b56598..a8`) and calls `wrapper2_dpotrf_`
(`0x100b565c8`). This is upper Cholesky R, covariance = R^T R.
The helper also includes banded/optimized branches: their roundoff behavior
is not reproduced by the scalar implementation.

Init multiplies factor diagonal entries (`0x10213f63c..688`), takes the
reciprocal and stores it at +0x210 (`0x10213f68c..694`). In apply:

- `0x10213ffcc` centers each row; `0x10213ffec` right-multiplies by the
  inverse factor stored at +0x160.
- `0x102140028..184` squares and sums resulting coordinates.
- `0x10213fef0..ff24` computes `sqrt(pow(2*pi, -D))`, using exact double
  bits `0x401921fb54442d18` for 2*pi.
- `0x10214019c..1ac` log mode returns `log(c) - 0.5*q`.
- `0x1021401bc..1d4` density mode returns `c * exp(-0.5*q)`.

For SPD covariance:

```
z = (x - mean) inverse(R)
q = sum(z_i^2)
c = sqrt((2*pi)^(-D)) / product(diag(R))
pdf = c * exp(-q/2)
```

Our implementation uses a lower Cholesky factor and triangular solve,
algebraically equivalent to this quadratic form. This is not a claim of
bit-identical Armadillo/LAPACK execution, nor a live reference comparison.
Strict symmetry, finite numbers and positive definiteness are our explicit
support policy; no covariance ridge, diagonal replacement or pseudo-inverse.

### Weighted density/peak pairs

Existing `probability.txt` at `0x100b1ef58` loops supplied Gaussian components.
It constructs MvnpdfTxf from a component mean/covariance (`0x100b1f170`),
evaluates input (`0x100b1f184`) AND the component's own mean
(`0x100b1f1c4`), then uses the component weight to accumulate both values
(`0x100b1f218..254`). Its two-output row is:

```
[sum_j(weight_j * pdf_j(x)), sum_j(weight_j * pdf_j(mean_j))]
```

The second value is the sum of each component's peak. It is not the
mixture evaluated at a single mixture mean. No weight renormalization
occurs in this bounded routine.

### Posterior, including appended slot

`posteriorCalculation` at `0x100b1f48c` copies column 0 using subview-copy
helper `0x100b1eae0`; that helper sizes/copies the subview (`0x100b1eb14..28`),
with an alias-copy branch, not a learned transform.
Then `0x100b23818` multiplies copied density and supplied prior elementwise
(`0x100b238d8..e4`, vector equivalents). Existing posterior body reduces
minimum of column 1, appends that minimum times scalar and normalizes:

```
w_i = density_i * prior_i
appended = min(peakDensity_i) * scalar
posterior = [w_0, ..., w_(C-1), appended] / (sum(w) + appended)
```

This closes the previously untraced working-vector construction in
`docs/MENTAL_POSTERIOR_DATAFLOW.md`. It does not by itself identify all
application neutral labels, class enumeration, thresholds or sensitivity
conversions; those belong to the caller/scoring investigation. The API
keeps the final slot as an appended candidate until that meaning is wired.

## Implementation and acceptance evidence

New internal files:
- `apple/Sources/EEGCore/ReferenceGaussianPipeline.swift`
- `apple/Tests/EEGCoreTests/ReferenceGaussianPipelineTests.swift`

`swift test --package-path apple --filter ReferenceGaussianPipelineTests`
passed 7 tests on 2026-10-10. Tests check non-square transform orientation,
K-1 truncation, correlated full-covariance analytic and 3x3 adjugate-oracle Gaussians, unequal
mixture weights/means/variances, prior/peak posterior arithmetic, one complete
explicit-feature-to-posterior workflow, and rejection without silent repair.
These are arithmetic/conformance tests, not vendor-output or physiology tests.

The new implementation is internal and not selected by any runtime profile.
All learned parameters are explicit inputs; no fabricated reference defaults.

## Required learned information and remaining gates

A fitted classifier needs selected-feature layout/front-end recipe, PCA
mean+basis, canonical mean+basis, component counts, means, full covariance
matrices, component weights, class priors, class order and caller scalar.
Their fitting procedures and exact deployed values are not recovered merely
by tracing inference. Vendor-held fitted matrices or generic baseline models,
if required to compare a specific existing vendor profile, are **asset
dependencies to discuss**, not data to silently copy. None were read or
included here. Independently fitting equivalent parameters requires tracing
training behavior and validating on separate recordings.

Still required: side-by-side output vectors with an authorized optional
Cortex reference, exact front-end ordering and selected features, training
recipe, all caller semantics, boundary/singular behavior qualification,
held-out cross-session performance and artifact-confound checks. No exact
parity, accuracy or production-readiness conclusion follows from these tests.
