# Singular PCA fitting composition

2026-10-11, M4 actual CortexService arm64, pinned SHA-256
`cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`.
Fresh static LLDB capture `fitting-callers.txt`; no process attach or vendor assets.

## Evidence-backed operation order

princompMultiClass invokes eig_sym on the pooled covariance at 4875c..48774,
then reverses all eigenvalue rows/eigenvector columns at 48780..48794. The
symmetric eigensolver wrapper uses a divide-and-conquer attempt followed by a
second solver on failure (49040..490b8). No strict-positive-eigenvalue condition
is visible in this caller or eig_sym wrapper. Zero roots survive decomposition;
our implementation rejects negative roots as an explicit PSD support boundary.

The count condition (48798..48850) checks **all** pooled counts <= dimension p.
If true, eigenvalue rows and matching eigenvector columns are clipped using the
first temporary count, min(n[0]-1,p), at 48854..488cc. For supported finite
counts>=2 the retained length is trunc(min(n[0]-1,p)-1)+1. This is not an
arbitrary numerical-rank or minimum-epoch rule. Existing ReferencePCALowEpoch
implements it, including its documented bounded exceptional-input policy.

Only after that caller returns does runPCA form percentages, cumulative sum,
find <=99 and choose dimensions. Fresh 47d10..47e30 captures rank/empty branches;
complete helpers are in `canonical-continuation-20261010/pca-rank-bartlett.txt`.
The percentage is 100*lambda/sum(lambda). If all roots are zero, 0/0 produces
NaNs and ARM unordered comparisons select nothing. runPCA clears its basis at
47e00..47e18. No forced minimum rank, identity basis or successful mock output.
If 0<selectedCount<K, it takes first K-1 columns; otherwise the found indices.

## Implementation

ReferenceTrainingEdgeCases now separates shared `psdEigenbasis` and
`pcaSelectedIndices` stages. Existing singularPCA calls both for its original
standalone contract. ReferencePCAFitting uses:

    ordered class pooling
      → PSD covariance eigenbasis (including zero roots)
      → finite low-epoch eigenpair clipping
      → nonnegative-spectrum rank selection
      → pooled original center + selected basis, or nil transform

This avoids duplicating eigensolver/rank code and fixes the former strict-SPD
stage that rejected a valid singular covariance before the traced rank logic.
Finite exact symmetry, negative-root rejection, dimensions<=70, LAPACK dsyev,
workspace checks and largest-coefficient-positive signs are our support choices.
Repeated eigenvalues have no uniquely determined vendor basis. Tiny numerical
negative roots are rejected, not silently clamped or made positive. Count-one,
unsigned exceptional-conversion and solver-failure branches remain unsupported.

## Canonical failed-Cholesky retry

Fresh 49e80..49f60 reconfirms the existing boundedCanonical trace: failed
Cholesky triggers diagonal additions of exact binary64 bit pattern
0x3ddb7cdfd9d7bdbb (1e-10), followed by retry. Existing
`training-edge-continuation-20261011` contains the complete body/equations.
Our caller-provided finite budget intentionally replaces the visible unbounded
vendor retry. Original within scatter is retained separately, repaired scatter
and addition count are returned; exhausted budget is explicit failure. No new
indefinite/exceptional or vendor-asset behavior is guessed.

At the initial PCA checkpoint, the following downstream gate remained:
ReferenceCanonicalScatter uses the strict-SPD projectDistribution validation.
A singular selected/projected covariance can still fail there explicitly.
This gate must be independently expanded against function-body evidence;
we do not claim full singular mental-command training is now verified.

## Validation and remaining gates

New analytic PCAFitting tests verify rank-deficient eigenvalues and selected
basis, all-zero pooled covariance returning nil, singular low-epoch clipping
before rank selection, and explicit indefinite rejection. Existing edge tests
retain generalized-eigen/jitter and bounded exhaustion checks. Test results are
recorded in the adjacent test log: 14 focused tests, zero failures at
2026-10-11 01:45:37 local time. Command:
`cd apple && swift test --filter "ReferencePCAFittingTests|ReferenceTrainingEdgeCasesTests"`.

No hardware/physiological trial or matching trained Cortex profile was used.
These are arithmetic conformance checks, not runtime output equivalence,
command accuracy, exact parity or production readiness. No vendor assets needed.

Follow-up: projection-singular-continuation-20261011 resolves the projection
gate from actual gaussianTransform bodies. CanonicalScatter now accepts bounded
PSD projection. Final singular Gaussian densities remain rejected explicitly.
