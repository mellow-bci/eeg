# Canonical decomposition continuation

These captures are actual function bodies from the pinned installed reference,
not learned model parameters. Identity and hashes are in manifest.json.

## Arithmetic now implemented in a bounded comparison kernel

`ReferenceCanonicalTraining.fit` takes explicit within and between scatter
matrices plus residual degrees of freedom and requested direction count.
It does not select epochs, pool class data or replace the acquisition/runtime
classifier. Its mathematical stages are:

1. In manova1Cov, total scatter is `(nTotal-1) covarianceTotal`
   (0x100b49cd4..0x100b49cf0, multiplication helper 0x100b55874).
   Within scatter accumulates `(nClass-1) covarianceClass`
   (0x100b49df8..0x100b49e18, scaled-add helper 0x100b55af8).
   Between scatter is total minus within (0x100b49e80, subtraction helper
   0x100b55db0). Scatter construction remains external to this kernel.
2. Cholesky decomposition of E at 0x100b49ed8 calls helper 0x100b56260.
   It passes triangle mode zero, selecting U at 0x100b56598..0x100b565a4
   and wrapper2_dpotrf_ at 0x100b565c8: `E=R' R`.
3. The transpose-and-inverse helper 0x100b57414 produces `R'^-1`.
   Nested multiplication at 0x100b49fb0 and the right-transpose multiply
   0x100b4dee4 produce `W=R'^-1 H R^-1`.
   W is averaged with its transpose and multiplied by 0.5
   (0x100b49fc8..0x100b4a0f0), then eig_sym is called at 0x100b4a140.
4. Helper 0x100b592d0 computes `B=R^-1 U` from the original upper
   Cholesky factor and whitened eigenvectors. Root/index ordering goes
   through SortingTxf(0,1,0), ascending. Subsequent reciprocal root storage
   reverses order (0x100b4a9b4), and the index array is reversed before
   canonical column extraction (0x100b4aac8..0x100b4ab04). Exact tie semantics
   remain unverified.
5. After root/index reordering, `B' E B` is calculated at 0x100b4ab40
   by helper 0x100b5b078/0x100b5b184. Its diagonal is divided by
   `nTotal-classCount` at 0x100b4ab74..0x100b4abb4 (0x100b5b400).
   Square roots at 0x100b4aeb4 and per-column division at 0x100b4af98
   normalize each direction to unit pooled within-class variance.

Our implementation uses equivalent lower-triangular solves instead of
explicit inverse matrices, LAPACK dsyev instead of the vendor's dc driver,
descending eigenvalues, and largest-coefficient-positive signs. These are
declared independent numerical policies. Repeated eigenvalues do not identify
a unique basis. Bitwise equality is not claimed.

## Gates deliberately not filled with approximations

- General epoch extraction selects entries strictly greater than 5. The
  reduction helper 0x100b4cf28/0x100b4d038 calculates an axis-0 arithmetic
  mean, but this is not a universal mean of qualifying counts. The pooling
  continuation traces a Cartesian row/column submatrix with duplicated indices;
  gaussianTransform reads the first element of its reduced 1xD result
  (0x100b49680..0x100b49684). This must not be assumed to establish MANOVA
  scalar-count semantics without tracing its own caller. The Cartesian helper
  is captured in pooling-continuation/mask-helpers.txt at
  0x100b2430c..0x100b2437c. Callers
  supply actual scatter matrices and scalar degrees of freedom explicitly;
  no scalar epoch-count replacement is installed by this kernel.
- The vendor retries failed Cholesky by adding a diagonal term (bit pattern
  0x3ddb7cdfd9d7bdbb, exactly 1e-10), inside an unbounded retry loop. Our kernel rejects
  singular within scatter; it does not claim that singular branch.
- Bartlett significance, alpha-dependent rank selection, full statistics
  outputs and final class statistics are not implemented by this kernel.
- Canonical direction count is supplied explicitly, not inferred from guessed
  significance parameters. Zero and negative roots are retained diagnostically.
- Feature selection and learned profile fitting remain separate gates.

## PCA dimension policy now traced and tested

`pcaSelectedIndices` receives positive descending covariance eigenvalues and
class count, preserving the actual runPCA selection branches:

- Divide by the eigenvalue sum and multiply by 100, then cumulative sum
  (helper 0x100b53f1c; fadd at 0x100b53f90).
- Find indices whose cumulative percentage is **<=99**, including equality.
  Helper 0x100b5414c skips only greater-than comparisons at 0x100b541dc..1e4.
- If the index count is zero, clear the PCA matrix at 0x100b47e00..18.
  Do not force a minimum rank. A leading component above 99% takes this path.
- For positive count below classCount, select first classCount-1 columns
  (0x100b47d08..40). For count at least classCount, select found indices
  (0x100b47d48..68). This excludes the component crossing 99%; it is not the
  usual policy of retaining enough components to explain at least 99%.

Full class pooling and selected-feature covariance construction are external
inputs. The implementation accepts only strictly positive descending roots;
that support boundary is ours. The eigenvalue sum/normalization and cumulative
floating-point operation order may differ in last bits from vectorized Cortex.

## Validation

`swift test --package-path apple --filter ReferenceCanonicalTrainingTests`
passed five tests. Independent analytic oracles cover diagonal roots,
noncommuting correlated scatters and generalized eigen-equations, pooled
variance normalization, zero/negative roots, and invalid/singular inputs.
PCA tests include exact 99%, zero-selection, count>=classes and the K-1 fallback.
There are no Cortex-observed output fixtures in these tests.

No vendor model assets are needed for this arithmetic. Exact matched-profile
verification still requires trained parameters and corresponding observed
outputs, kept local for comparison. No runtime dependency or proprietary asset
is added.
