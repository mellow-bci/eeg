# Canonical class construction and MANOVA scatter

2026-10-11, actual installed M4 arm64 CortexService; pinned binary SHA-256
`cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`.
Static LLDB only, no vendor process invocation or proprietary trained assets.
New capture `scatter-callers.txt` supplements existing function-body captures.

## Exact arithmetic and ordering

For each ordered class, runCanonicalDecomposition requires exactly one Gaussian
(getNumOfGaussianData, 0x100b480cc..480d4), invokes gaussianTransform with the PCA
basis (0x100b4819c..481b4), and then combineGaussian on the accumulated projected
Gaussian and the newly projected class, with boolean false (0x100b481e0..481f0).
It does **not** pool original class Gaussians and then project the pooled Gaussian.

For input class mean mu_i, covariance C_i, and basis P (input rows, output columns):

- projected mean = mu_i P, with no subtraction;
- projected covariance = P^T C_i P;
- projected counts repeat the first column mean of the Cartesian >5 count
  extraction across the output dimensions. A one-row input reduces to its first
  strictly >5 count, not the average of all feature counts.

Projection evidence: `training-followup-20261010/distribution-count.txt` and
`epoch-count-continuation-20261010/mean-helpers.txt`; count primitive already exists
in ReferenceEpochCounts. Projection and sequential pooling arithmetic reuse the
existing tested comparison kernels. Timestamp handling is intentionally absent
from this new contract; internal zero timestamps are placeholders, never exported
as a measurement or claimed to recover gaussianTransform metadata.

Given the sequentially pooled projected covariance C and effective scalar count
N, manova1Cov constructs:

    T = (N - 1) C
    E = sum_i (n_i - 1) C_i_projected
    H = T - E
    residual df = N - K

Total count extraction, dimension-0 mean and first-result read occur at
0x100b49c48..49cc8. Total scaling is 0x100b49cd0..49cf0. E is zero initialized
at 0x100b49d18. Each class count/covariance and scaled accumulation occur at
0x100b49d88..49e18. H subtraction is 0x100b49e68..49e80.
Scalar multiplication/addition/subtraction helpers 0x100b55874, 0x100b55af8,
0x100b55db0 have actual bodies in `canonical-continuation-20261010/helpers.txt`;
zero-fill helper 0x100b4ed08 is captured in
`training-statistics-continuation-20261010/coordinate-assignment.txt`.
Residual df subtraction is 0x100b4ab74..4ab78 in
`canonical-continuation-20261010/tail-count-product.txt`.

Class means affect H via the pooled covariance. We do not substitute a separate
between-class outer-product formula for this observed T-E path.

## Implementation boundary and tests

`ReferenceCanonicalScatter.construct` accepts explicit ordered class statistics,
PCA basis and maximumClasses. It returns projected classes, pooled statistics,
counts, T/E/H and residual df. Exactly two or more classes, nonzero dimensions
<=70, finite counts with qualifying >5 values and strictly SPD input/output
covariances are our bounded support policy; unsupported singular/zero-rank
projection fails explicitly. The 70 limit and caller-provided class capacity are
not claims about vendor limits. It does not choose PCA dimensions or canonical
rank, fit windows, accept a training run, infer sensitivity, or return a command.

Analytic tests cover uniform-count scatter, heterogeneous feature counts showing
projection-before-pooling semantics, uncentered dimension-reducing projection,
and explicit unsupported/capacity failures. Root reported consolidated validation: 115 tests, 2 skipped, 0 failures, including
all four new ReferenceCanonicalScatterTests. These are arithmetic fixtures, not
a trained Cortex profile oracle.

## Runtime center remains unresolved

The exposed pooled mean is provenance. This routine does not claim it is the
mean stored in a runtime PCA/canonical transform. runCanonical passes its output
matrix and Stats structure to manova1Cov at 0x100b48260..48284, then copies the
Stats-adjacent GaussianAlgebra vector at structure+0x668 to the output vector
(0x100b48288..482bc, helper 0x100b25c6c). These instructions do not establish a
runtime center assignment. Storage/construction and upstream transform mean
contracts still require separate tracing and matching trained reference outputs.
No vendor assets are required for the implemented arithmetic; a genuine trained
reference profile and matched outputs remain required for full numerical parity.
