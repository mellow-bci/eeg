# PCA class pooling and center reconstruction

Static arm64 CortexService reference SHA-256:
`cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`.
No vendor executable, profile, learned matrix or model asset is distributed here.
These captures are function-body evidence, not matched runtime predictions.

## Proven normal-support recipe

`runPCA` (`0x100b47ac8`) calls `princompMultiClass` (`0x100b4851c`) at
`47b08`, passing output eigenvectors, center at output+`0xb0`, and eigenvalues
at output+`0x160`.

`princompMultiClass` requires exactly one GaussianData in each class
(`485c8..485d0`). It starts an empty accumulator, then in class vector order
copies the accumulator and invokes `combineGaussian(accumulator, class[0],
output, false)` (`485d4..4861c`). The already documented pooling equations
therefore apply across classes as well as within a class. The timestamp fold
remains ordered; it is not a global arithmetic mean.

At `4875c` it obtains the resulting covariance and invokes the symmetric
eigensolver wrapper `48f74` at `48774`. This uses the **pooled covariance
directly**: it does not rebuild a PCA scatter matrix from raw epochs and does
not average class covariances without the between-mean pooling terms.
The `dc` method first attempts `546a8`, then falls back to `54a64`
(`49084..490b0`). `54dd8` reverses eigenvalue rows (`54eb0..54ec4`), and
`55060` reverses eigenvector columns (`5518c..551f8`), giving descending order.

At `488d4..4896c`, the pooled average vector is copied to the caller's center.
Thus the comparison transform is `z = (x - pooledMean) B_selected`. This is
distinct from `gaussianTransform`, which projects stored Gaussian means
without subtracting that center; downstream assembly must preserve that
distinction.

`runPCA` retains the already traced cumulative-percentage policy:
`cumsum(100*eigenvalues/sum(eigenvalues)) <= 99`, with its class-count floor
only when the found index vector is nonempty. Empty selection clears the PCA
matrix (`47e00..47e18`). It is an abort, not an invented minimum of one.

## Implemented boundary

`ReferencePCAFitting.fit` accepts one Gaussian per class and executes the
ordered pooling, strict-positive symmetric covariance decomposition, selected
basis and pooled center recipe. It returns a nil transform on empty selection.
It leaves the independent runtime trainer unchanged. LAPACK `dsyev`, sign
normalization, strict positive definiteness and the 70-feature limit remain
our numerical/support choices, not recovered vendor parameters. Repeated
eigenvalues do not determine an exact vendor basis.

## Low-epoch clipping: traced but deliberately not implemented

The temporary count vector is formed as `min(n[f]-1, p)`
(`486b0..48754`, including vectorized tail `48a48..48b18`), where `p` is the
pooled average vector's element count. The code then tests whether **all**
original pooled feature counts satisfy `n[f] <= p` (`48798..48850`). Only that
all-true branch clips eigenvalue rows and eigenvector columns using the first
temporary count (`48854..488cc`), converted with unsigned truncation.

The Swift bounded recipe explicitly rejects this branch. In particular it
does not silently replace this logic with `min(counts)`, a sample count sum,
`N-K`, or numerical matrix rank. Edge cases near zero/one counts and unsigned
conversion saturation need a separate analytic conformance fixture before
expanding support. No vendor asset is required for that work.

## Remaining canonical construction boundary

The existing `manova1Cov` trace proves total scatter `(N-1) Cov_total`, within
scatter `sum_c (N_c-1) Cov_c`, and between scatter `total-within`
(`49cd4..49cf0`, `49df8..49e18`, `49e80`). These quantities must use the
caller's actual epoch extraction/reduction, not assumed scalar epoch counts.
The extraction helper is `0x100b4c2fc`; its strict comparison and Cartesian
submatrix semantics are documented by the pooling continuation. Reduction
helpers `0x100b4cf28` and `0x100b4d038` perform axis-zero means; the precise
shape/first-element selection at each MANOVA caller still requires composition
review. The normal PCA recipe above requires none of those substitutions.

## Validation

Three new analytic tests check weighted pooling/center and eigenvalues
(`182/39`, `38/39`), dominant-root empty-selection abort, and explicit invalid
class/low-epoch failures. Parent's consolidated run passed 115 tests with two
skips and zero failures, including these three tests. No claim of
trained Cortex profile equivalence is made.

Capture reproduction:

```sh
ssh -o BatchMode=yes m4 'lldb -b -o "target create --arch arm64 \"/Applications/EmotivApps/EMOTIV Launcher.app/Contents/MacOS/CortexService\"" -o "disassemble -n Cortex::MentalCommands::GaussianTraining::runPCA" -o "disassemble -n Cortex::MentalCommands::GaussianTraining::princompMultiClass" -o "disassemble -s 0x100b48f74 -e 0x100b49468" -o "disassemble -s 0x100b54dd8 -e 0x100b55300" -o quit'
cd apple
swift test --filter ReferencePCAFittingTests
```
