# MANOVA Bartlett diagnostics continuation

Static arm64 function-body inspection of the installed CortexService. Captured
files and supporting captures are hashed in `manifest.json`. No executable,
profile, learned matrix, credentials or vendor model asset is included here.

## Proven arithmetic

The complete `GaussianTraining::manova1Cov` is available across
`training-followup-20261010/pca-canonical.txt` (0x100b49b04–0x100b4ab00)
and `canonical-continuation-20261010/tail-count-product.txt`
(0x100b4aafc–0x100b4c2fc). `manova-tail.txt` captures the diagnostic setup
again for local address continuity. Helper bodies already captured by the
canonical agent remain referenced rather than duplicated.

Let p be feature width; K be Gaussian class count; N be the effective count
already computed by the caller. This continuation does not redefine N.

1. The eigenvalue/index matrix is sorted ascending by root at 0x100b4a594.
   Row 0 is roots, row 1 is coordinate indices. SortingTxf argument semantics
   are independently recorded in `feature-selection-continuation/TRACE.md`.
2. 0x100b4a660–0x100b4a66c verifies the first ascending root is greater than −1.
3. 0x100b4a670–0x100b4a674 sets r=min(p,K−1).
4. 0x100b4a8ec–0x100b4a914 constructs roots+1; helper 0x100b5a75c
   performs elementwise scalar addition.
5. 0x100b4a928 invokes 0x100b5a490 with axis=0. The new
   `product-helper.txt` proves this is a cumulative product, not a reduction:
   0x100b5a4ec initializes the accumulator to 1, then 0x100b5a4f0–500
   multiply and store each accumulated value. The multi-column branch
   0x100b5a5ec–610 does the same per column.
6. 0x100b4a9b4–0x100b4a9c8 reciprocates and reverses those products.
   0x100b4aa04–0x100b4aa30 retains the first r values. Thus for ascending
   e[0...p−1], lambda[k]=1/product(i=0...p−1−k)(1+e[i]). All p roots
   contribute before rank truncation.
7. 0x100b4aa38–0x100b4aa58 forms multiplier=−(N−1−(p+K)/2).
   0x100b4aa6c invokes helper 0x100b5a9ec; its 0x100b5ab5c–0x100b5ab6c
   scalar loop calls log and multiplies. Statistic[k]=multiplier*log(lambda[k]).
8. 0x100b4aa70–0x100b4aaac creates index vector k=0..<r with scalar p
   and K−1. Helper 0x100b5acdc is **not a probability/CDF helper**:
   its 0x100b5adb0–0x100b5add0 and 0x100b5ae2c–0x100b5ae38 directly
   evaluate (scalarA−entryA)*(scalarB−entryB). Hence df[k]=(p−k)*(K−1−k).

The K mapping is supported by vector span/division at 0x100b49bcc–49be4,
K saved at sp+0x18 (0x100b49d2c), K−1 at sp+0x20
(0x100b49cf4), reload into x26 (0x100b49e84) and K reload into x24
(0x100b4a9fc). The degrees-of-freedom vector is copied to Stats+0x390
at 0x100b4b418–0x100b4b4bc. Roots are copied to Stats+0x440.

## Alpha and rank boundary

The incoming d0 alpha is checked against 0 and 1 at 0x100b49b54–49b60.
Invalid alpha follows the warning/return path. The valid branch at 49bc8
does not store alpha in a saved register or stack slot; the first subsequent
function call overwrites d0. Consequently this captured body **does not use
alpha to select significant roots**. No chi-square CDF, p-value calculation
or alpha comparison was found in its complete function body. A familiar
MANOVA formula must not be treated as evidence for a missing statistical test.

w28 is a separate zero-width branch flag: 0x100b4a1dc jumps to 4a274
only for zero p, setting w28=1; the ordinary nonzero path sets w28=0 at
4a554. Its later matrix truncation branches are not alpha decisions.

`ReferenceBartlettSelection` therefore exposes diagnostics only, with no
selected-rank result. Exact downstream interpretation still requires tracing
consumers of the Stats vectors and any separate rank/significance policy.
No such policy, default alpha or chi-square cutoff is invented here.

## Implementation boundary and validation

The comparison primitive accepts full ascending finite roots >−1, K>=2 and
the already derived positive finite N. These bounded input checks and explicit
overflow errors are our guardrails, not recovered vendor error policy. It
preserves cumulative multiplication, reciprocal, log and multiplication order;
it does not substitute logarithm sums or stabilize overflowing products.
It is not connected to acquisition, the production profile path or inference.

`cd apple && swift test --filter ReferenceBartlettSelectionTests` checks an
analytic [0,1,3] case, full-root contribution before truncation, zero diagnostics,
invalid domains/order and explicit overflow. These are arithmetic tests, not
Cortex output comparison or hardware/mental-command validation. A trained
reference profile and matching outputs are still needed for numerical end-to-end
comparison. No vendor learned assets were needed for this bounded arithmetic.
