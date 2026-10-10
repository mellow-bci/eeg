# Training continuation: body evidence and boundaries

Reference identity and capture hashes are in manifest.json. This is static
function-body analysis, not execution against a trained vendor profile.

| Stage | Body evidence | Implementation / remaining gate |
| --- | --- | --- |
| Gaussian pooling | combineGaussian 0x100b466e0; fit-entry.txt plus fit-core.txt cover its body. Empty inputs reset/copy. At 0x100b469a0 and 0x100b469bc both epoch counts must exceed 1 to enter the selected-coordinate list. | Count masks, matrix-expression helpers, covariance merge and boolean mode still need complete semantic tracing. Do not replace these with one scalar sample count. |
| Feature selection | Full runUnivCoordSelection in selection-neutral.txt. Requires multiple classes, reads averages/covariances/counts, invokes AggregateTxf and SortingTxf before subselecting Gaussian data. | The complete score formula, aggregation mode, threshold rule and ordering semantics are unresolved. No ranking approximation is installed. |
| PCA covariance eigenbasis | princompMultiClass calls covariance getter at 0x100b4875c, eig_sym helper 0x100b48f74, then reverse helpers at 0x100b48788 and 0x100b48794. runPCA normalizes eigenvalues and invokes cumulative-sum/selection helpers. | Explicit-covariance eigendecomposition arithmetic implemented. Class pooling, rank truncation and full fitted recipe remain unresolved. LAPACK dsyev and sign normalization are independent numerical choices, not recovered vendor defaults. |
| Canonical fitting | runCanonicalDecomposition projects class Gaussian data with gaussianTransform, combines distributions, and calls manova1Cov at 0x100b48284. manova1Cov checks significance-level range and extracts counts with threshold 5. | MANOVA whitening, significance selection and canonical basis calculation not yet implemented. The existing explicit-basis inference remains separate. |
| Gaussian distribution projection | gaussianTransform: mean multiplication 0x100b494d0; covariance left multiplication helper at 0x100b49564 followed by right multiplication 0x100b495d0. Helper 0x100b50500 is also used for self-products in combineGaussian. | Implemented mu B and B^T Sigma B arithmetic. Does not reproduce GaussianData epoch-count propagation, update time or full training routine. Strict SPD input/output and mirrored covariance storage are our stated support policies. |
| Epoch extraction | Full extractNumEpochsGreaterThan in distribution-count.txt. Nested row/column scan uses column-major offset rows*column+row and rejects count <= threshold at 0x100b4c3e8. Selected-index helpers construct the output. | Need resolve paired-index versus matrix-subview semantics before implementing general matrix extraction. No fabricated scalar replacement. |
| Neutral autosampling | Full runAutoSamplingNeutral, started and completed routines in selection-neutral.txt. Reads trainingControl/autoSamplingNeutral, appends valid nonempty matrix input, checks accumulated size against member at +0xb0 on stop, sets training action 1 and rebuilds/saves classifier. Failure path clears classifier. Started/completed lock/unlock training action, active actions, activation/action thresholds and rebuildSignature. | Configured accumulation target, buffer helpers, upstream validity flag semantics and independent acceptance lifecycle remain unresolved. Existing neutral scoring is tested, but autosampling is not claimed reproduced. |

Projection tests use analytical correlated covariance and an invertible change
of variables: transformed density equals original density divided by the
absolute determinant. The eigenbasis test reconstructs the covariance and
checks projected diagonal values. These are independent mathematical oracles;
none are Cortex-observed outputs. Repeated eigenvalues do not determine unique
eigenvectors, and floating point/sign conventions may differ from Cortex.

The covariance left-product helper is captured in transpose-product.txt:
0x100b506b4 sets CBLAS transpose (112), 0x100b506b8 sets no-transpose (111),
and 0x100b506c4 invokes wrapper_cblas_dgemm. This supports B^T Sigma rather
than inferring transpose solely from the gaussianTransform function name.

No vendor model assets were needed for these arithmetic stages. Matched-profile
comparison still requires the participant-trained PCA/canonical parameters,
Gaussian parameters, selected coordinates and corresponding observed outputs.
M4's checked training-attributes store was empty. No trained parameters or
decrypted database are included here. Offline tracing continues without a new
participant trial; exact end-to-end parity remains unverified.

Next implementation order: resolve the pooling matrix helpers and masks;
derive feature-selection score/cutoff; close PCA rank policy and MANOVA basis;
implement versioned independently fitted training with explicit acceptance;
close neutral accumulation/reset semantics; finally compare identical inputs,
parameters and observed stages with Cortex. Keep the existing acquisition and
independent runtime recipe unchanged until those comparison gates pass.

Validation: `swift test --package-path apple --filter 'Reference|Decoder'`:
37 executed, two explicit skips, zero failures. External Cortex comparison is
one skipped test because no matched fixture exists; it is not a parity pass.
