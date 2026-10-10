# Singular Gaussian projection before canonical fitting

## Source evidence

Pinned M4 CortexService arm64 SHA-256: `cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`. Static LLDB only; no profile/model assets copied and no vendor process executed by this capture.

`gaussianTransform` starts at `0x100b49468`. Normal path gets the average at `4949c`, multiplies the row mean by the supplied basis at `494d0`, and sets it at `49524`. It gets covariance at `49538`, calls `50500` with basis and covariance at `49564`, multiplies that temporary by the basis at `495d0`, and sets covariance at `49608`.

Helper `0x100b50500` checks multiplication dimensions (`5051c..5052c`) and allocates basis-columns by covariance-columns (`50534..50538`). Its generic multiplication calls `wrapper_cblas_dgemm` at `506c4` with column-major 102, first operand transpose 112, second operand no-transpose 111, alpha 1, beta 0 (`506a0..506c4`). The normal projection is therefore:

- `mean_projected = mean * P` (uncentered).
- `covariance_projected = transpose(P) * covariance * P`.

Neither the projection caller nor this matrix-product helper performs Cholesky, inversion or a strict-positive-definite test. A singular covariance is a valid matrix input to this arithmetic. The existing reference projection's scoring-time density checks were our support restriction, not a recovered vendor projection condition.

Count handling remains the independently traced first qualifying (>5) count repeated over projected coordinates; see the earlier epoch-count and canonical-scatter traces. No count policy was changed here.

## Implementation and policies

`ReferenceGaussianProjection` supplies the same arithmetic for finite symmetric PSD inputs, including zero eigenvalues. It inserts no jitter, variance floor, inverse or pseudoinverse. Exact symmetry, negative-root rejection, nonnegative finite metadata weight, LAPACK behavior, dimension 1...70 and finite-result checks are independent bounded comparison policies. Symmetric output storage matches our existing roundoff convention; vendor BLAS rounding is not asserted bit-identical.

`ReferenceCanonicalScatter.construct` now uses this arithmetic before pooling/scatter construction. Canonical retry still adds the traced `1e-10` only to within-class fitting scatter with an explicit bounded retry budget. Original projected class covariance is preserved.

This does **not** relax final runtime scoring: `ReferenceRuntimeTransforms` and Gaussian density retain their strict-SPD gate. Repairing fitting scatter does not establish positive variance in every final class density. No evidence here supports silently repairing final class covariance, and no such repair was added.

## Verification and scope

Five new projection tests cover exact singular directions, projection into a positive-variance subspace, zero within scatter with the explicit canonical retry, agreement with the old SPD kernel, and malformed/indefinite rejection. A new full `construct -> boundedCanonical` analytic test exercises zero class covariances through the actual scatter API, verifies between scatter 64 and one diagonal addition, and confirms singular class density still fails explicitly.

The final coordinated Reference|Decoder run executed171 tests:169 passed,2 missing reference fixtures skipped,0 failures. All six new projection/scatter tests passed. Shared projection arithmetic is reused by the strict scoring wrapper; no duplicate projection pipeline remains. `git diff --check` passed. These are analytic implementation checks, not observed Cortex trained-profile inference or physiological/hardware validation. No vendor assets needed for this arithmetic.

Runtime assembly now also uses the shared PSD projection before validating the
FINAL class density. A singular intermediate may yield positive final variance;
no covariance repair is applied. The full fitted-workflow test follows singular
class statistics through pooling, PCA, scatter/canonical fitting, runtime
assembly and Gaussian posterior inference. The runtime subspace test separately
checks positive output variance and rejects a zero-variance final direction.
