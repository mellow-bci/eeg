# Numerical fitting gates audit

Read-only audit, 2026-10-11. This document reconciles actual captured Cortex
function bodies with the current independent sources. No new binary capture,
vendor execution, profile asset, source change or test run was performed here.
The referenced captures identify the installed M4 arm64 binary SHA-256 as
`cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`.

## Already closed: do not schedule these as missing algorithms

| Former gap | Actual body evidence | Current implementation and boundary |
| --- | --- | --- |
| Singular PCA rejected before rank selection | `singular-continuation-20261011/fitting-callers.txt`: princomp calls eig_sym at `0x100b4875c..48774`, reverses eigenpairs `48780..48794`; no positive-root test in that caller | `ReferencePCAFitting.fit` uses shared `ReferenceTrainingEdgeCases.psdEigenbasis`, retains exact zero roots; negative roots, exact symmetry and LAPACK behavior remain explicit independent support policies |
| Low-epoch clipping unknown | `low-epoch-continuation-20261011`: all counts <= p at `48798..48850`; temporary min(n[f]-1,p) at `486ec..48754`; first temporary count minus one converted at `48860..4886c`, matching pair slices at `488a0/488cc` | `ReferencePCALowEpoch.apply` covers finite counts >= 2; exceptional unsigned conversion is intentionally excluded |
| Empty-spectrum rank forced or missing | `training-edge-continuation-20261011`: percentage/cumulative <=99 comparison helper `0x100b541dc..541e4`, clear basis at `47e00..47e18` | Shared nonnegative rank selection returns no transform for all-zero roots. Do not invent a minimum rank or successful identity basis |
| Canonical singular retry absent | Complete body in `training-followup-20261010/pca-canonical.txt`, `49ea8..49f3c`: failed Cholesky calls `560bc` then adds diagonal bit pattern `0x3ddb7cdfd9d7bdbb` (1e-10), retries | `ReferenceTrainingEdgeCases.boundedCanonical` already implements additive retry with explicit caller budget; vendor visible loop has no attempt cap. No default budget should be inferred |
| Projection blocked by scoring-time Cholesky | `projection-singular-continuation-20261011/gaussian-projection.txt`: `gaussianTransform` `49468`, mean product `494d0`, covariance product `49564/495d0`; helper `50500` performs transposed BLAS multiplication, not density validation | `ReferenceGaussianProjection` supplies PSD projection to `ReferenceCanonicalScatter` and `ReferenceRuntimeTransforms`; original class covariance is preserved without repair |
| Full fitter has not composed singular scatter/retry | Current `ReferenceClassifierRebuild.fit` | Already composes preparation -> PSD PCA -> PSD projection/scatter -> bounded canonical retry -> runtime assembly -> signature. No integration code change is needed to connect these APIs |
| Bartlett significance/root-rank algorithm missing | `bartlett-continuation-20261010`: alpha validated `49b54..49b60` but not used on the valid branch; cumulative-product helper `5a490`, logs `5a9ec`, degrees-of-freedom helper `5acdc` | Diagnostics are traced. There is no evidence to insert a chi-square CDF or alpha-selected rank. Current fitter supplies K-1 directions. Old notes describing an unknown CDF/alpha cutoff are stale |
| Runtime center construction unknown | `runtime-centering-continuation-20261011` plus `ReferenceRuntimeTransforms` | PCA runtime center is assembled explicitly; canonical runtime center is zero; fitted means center by pooled projected mean. Heterogeneous-count center mismatch remains observable, not corrected |

Earlier canonical/scatter TRACE files record restrictions as of their original
checkpoint. Their strict-SPD projection/PCA limitations must be read with the
later singular and projection continuations; they are not current stack gaps.

## Actual remaining numerical work queue

1. **Complete eigensolver leaf/failure behavior, then qualify numerics.**
   The captured wrapper `0x100b48f74` accepts method `d` or `s` and has actual
   calls `49080 -> 5465c`, `49098 -> 546a8`, then fallback
   `490ac -> 54a64`. The body shows fallback control flow; checked evidence
   contains these call sites but not complete bodies for those three leaves.
   Capture the leaves and their LAPACK wrapper/info handling before asserting
   exact failure, tolerance, workspace or repeated-root behavior. Independent
   `dsyev`, largest-coefficient-positive signs, rejection of any negative root
   and exact-symmetry requirements are not recovered vendor numerical policies.
   Repeated eigenvalue bases are nonunique; compare subspaces and resulting
   scores, not arbitrary eigenvector columns. Tiny negative roundoff roots must
   not be silently clamped without either explicit independent policy or proof.

2. **Resolve inverse dispatcher branches actually selected in canonical fit.**
   Canonical caller `49f74 -> 57414 -> 57690` computes transpose-factor inverse;
   `4a174 -> 592d0` constructs the final inverse-factor/eigenvector product.
   `canonical-continuation-20261010/chol-inverse-count.txt` captures dispatch
   `57690` and only the beginning of small-size helper `579a8` (size <=4 jump
   table; general branch `579d4 -> 57fbc`). Its further dispatch targets include
   `57700 -> 580ec`, `57958 -> 58520`, `57974 -> 588ac`, and
   `57990 -> 58344`; complete leaf bodies are not in the checked captures.
   Do not label those leaves pseudoinverses/SVD solely by branch shape.
   Identify caller matrix flags, dimensions and chosen branch, then trace
   determinant/tolerance/failure behavior. Current scalar triangular solves
   implement the supported algebra, not all vendor optimizations or low bits.

3. **Final singular class density remains an explicit failure, distinct from
   repaired fitting scatter.** `ReferenceRuntimeTransforms.assemble` projects
   PSD class statistics, then invokes `gaussianDensity` on each FINAL class;
   `ReferenceSignatureTraining.assemble` repeats density admissibility before
   creating single-component mixtures. The density kernel requires exact
   symmetry and strictly positive Cholesky residuals. Consequently a class can
   pass PCA/scatter/retry but fail because its final covariance has zero
   variance. Canonical diagonal additions only change fitting within scatter,
   not the original class covariance. They do not justify density jitter.
   Actual `MvnpdfTxf::init` at `0x10213f40c` calls Cholesky `560bc` and inverse
   `102140620`; the latter's captured `102140654/698 -> 57690` failures clear
   output rather than documenting a singular Gaussian probability model.
   Trace the init/factory/caller failure propagation and leaf inverse behavior
   before expanding final-density support. There is currently no evidence to
   add a variance floor, pseudodeterminant, or successful singular density.

4. **Exceptional count conversion and singleton shapes remain bounded out.**
   Clipping `48868/4886c` subtracts one then `fcvtzu`; the finite >=2 recipe is
   recovered, but zero, NaN, infinity and negative inputs are not supported
   comparison cases. Ordinary covariance helper `4d73c..4d784` transposes
   F-by-1 input into a row vector, dividing by max(F-1,1); F>1,N=1 subsequently
   conflicts with F-by-F scatter source shape at `4f4a4..4f4bc`.
   Document actual malformed-input failure, not invented singleton variances.

5. **Matched reference outputs are still required.** Analytic fitting tests
   establish equations and controlled composition. They do not measure output
   equivalence on a trained Cortex profile, numerical branch selection under
   real features, or physiological command discrimination. Need independent
   training inputs plus matching Cortex intermediate/output observations;
   cross-session evaluation remains separate. No trained model asset is needed
   for static numerical leaf tracing. If trained-profile observations are later
   used, they remain optional local comparison material, not deliverable assets.

## Exact proposed verification changes (no source changes in this audit)

No missing retry-composition implementation was found. Add regression tests to
the existing `ReferenceClassifierRebuildTests` around its public `fit` entry,
rather than introduce another fitter:

- Singular input covariance with positive variance in the retained runtime
  direction: full fit, serialization/reload if desired, finite scoring.
- A genuinely zero within-scatter fixture reaching the retry stage: budget zero
  must fail there; adequate budget must pass the canonical stage, with the final
  zero-variance density still rejected explicitly if no scoreable subspace
  exists. Avoid claiming that canonical success implies signature success.
- Empty pooled PCA covariance: `.emptyPCASelection`, no forced rank.
- Ill-conditioned/repeated-root fixtures: invariant subspace/equations and
  finite scores where supported; separately compare vendor outputs after leaf
  tracing. Do not impose arbitrary eigenvector signs as a vendor assertion.

Existing `ReferenceFittedWorkflowTests` covers singular input projection into a
positive-variance subspace through the stage APIs, but directly uses the strict
canonical kernel. `ReferenceGaussianProjectionTests` covers explicit canonical
retry after zero within scatter. Public rebuild-entry coverage would protect
composition without duplicating either algorithm. No tests were executed by
this audit, and no exact parity or production qualification is claimed.
