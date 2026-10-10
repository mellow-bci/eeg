# Runtime centering and final Gaussian projections

2026-10-11, installed M4 arm64 CortexService SHA-256
`cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`.
Static LLDB function-body captures only. No assets or vendor code are bundled.
This resolves the builder path; imported classifiers remain their own contracts.

## Storage to runtime

- runPCA supplies center output+0xb0 to princompMultiClass at 47afc..47b08.
  princompMultiClass copies its sequentially pooled original mean into that output
  at 488d4..4896c (existing `pca-fitting-continuation-20261011` bodies).
- buildSignatureFromPCA copies PCA center sp+0x920 to classifier+0x180 at
  44ee0..44f84, and PCA basis sp+0x870 to classifier+0xd0 at 44f88..4502c.
- manova1Cov initializes its x2 output matrix to **zeros**, shape of the pooled
  projected mean, at 49bf8..49c1c. Fresh helper 55750 body resolves the previously
  uncertain fill: xzr stores at 557e0..55800 or bzero at 55830. It is not ones.
  The output pointer is x22 until 49c40 replaces x22 with dimension; subsequent
  normal path constructs Stats separately. There is no learned-mean assignment
  to this output matrix in the captured complete manova body.
- buildSignatureFromPCA copies that Manova_struct base matrix to classifier+0x2e0
  at 45030..450d0. This is the runtime canonical center, zero on this builder path.
- Canonical basis is Stats+0x4f0 (Manova_struct+0x5a0), assigned from sp+0xbb0
  at 4b4cc..4b570, copied to classifier+0x230 at 450d4..45178.
  Do not confuse that basis matrix with a center.
- Classification::run passes classifier+0xd0 as PCA basis and +0x180 as center
  at 1e034..1e044; passes +0x230 as canonical basis and +0x2e0 as center at
  1e120..1e134 (existing `classification-run.txt`).
- Both transform routines call helper20928 with input and their center. Fresh
  body shows input minus center (`fsub` at 209b0..209bc and scalar tails), then
  multiplication helper22ea8. Canonical selects the first K−1 basis columns
  for K>=2 (existing `canonical-transform.txt` and tested kernel).

Therefore for selected feature row x and learned PCA basis P, canonical basis B:

    runtime z = (x - originalPooledMean) P
    runtime y = z B[:, 0..<K-1]        // canonical center = zero

No projected pooled center is subtracted again at runtime.

## Final class Gaussians

runCanonical first projects class means/covariances uncentered through P and
sequentially pools those projected class statistics (prior scatter trace).
Call 4b804 gets projected class mean and 4b810 gets pooled projected mean.
These are passed as subtraction expression to helper5bbb4 with B at sp+0xbb0
(4b818..4b854). Helper5bbb4 invokes actual subtraction helper55db0 and
matrix multiplication helper22ea8 (5bbe0..5bc04). Then 4b864 invokes helper4d528
with string "std". Fresh 4d528 body identifies **in-place simple transpose**
(`inplace_strans` error string), not standardization or a variance operation.
The stored per-class mean is a column representation of:

    finalMean_i = (projectedMean_i - pooledProjectedMean) B

Covariance caller4b884..4b8ac passes class projected covariance with B and its
transposed form into helper5bd08. Fresh helper body shows association variants
of three matrix multiplications, preserving:

    finalCovariance_i = B^T projectedCovariance_i B

The resulting mean vector is at Stats+0x5b8 (Manova_struct+0x668), copied by
runCanonical at 48288..482bc to its output vector. Builder uses those means at
454fc..45518 and covariances at 45364..45410; unit weight1 is independently
resolved in `signature-continuation-20261011`.

## Heterogeneous counts caveat

Original pooling weights each feature by its own count. gaussianTransform
reduces each class's counts to its first >5 effective count and repeats it.
Consequently originalPooledMean*P need not equal pooledProjectedMean.
The builder's final class means and runtime feature centering can then differ.
This is an observed arithmetic consequence, not a claimed hardware bug.
ReferenceRuntimeTransforms reports their difference and does not silently repair
or replace either center. Matched trained profile/runtime outputs are needed to
quantify whether this occurs in the deployed training path.

## Comparison implementation

New internal ReferenceRuntimeTransforms assembles explicit PCA center/basis,
resolved scatter output and explicit canonical basis; returns zero-centered
canonical runtime transform, final unit-weight classes and the center diagnostic.
It uses the existing transform/projection/density kernels, one canonical path.
Finite/SPD support, <=70 dimensions and explicit failure states are our comparison
boundaries. No windows, acceptance, class priors, neutral scales or sensitivity
are inferred. Three analytic tests cover nonzero original PCA center (preventing
accidental double-centering), final covariance/unit weight, heterogeneous counts
without correction, and unsupported inputs. These do not constitute Cortex output
parity or physiological command accuracy. Root coordinates consolidated tests.

No vendor assets were required. Remaining gates: fitted reference profile and
matching feature/output oracle; complete broader lifecycle and deployment checks.
