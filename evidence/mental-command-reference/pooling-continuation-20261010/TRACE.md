# Gaussian pooling: arithmetic and mask evidence

The pinned installed binary and captured-file hashes are in `manifest.json`.
All evidence is static function-body analysis. No trained profile, Cortex
execution output, vendor binary or vendor model asset is part of this change.

The entry/body callers remain in `../training-followup-20261010/fit-entry.txt`
and `fit-core.txt`. Newly captured helpers are in this directory.

## Derived supported operation

Inputs have feature count row vectors nA/nB, mean row vectors mA/mB and square
covariance matrices CA/CB. The implementation uses native Swift arrays with
explicit row/column indexing; it does not reproduce Armadillo storage objects.

1. Empty inputs copy the nonempty input; both empty reset. Calls at
   0x100b46724 through 0x100b467e8 support these branches.
2. The default output is copied from the input with greater minimum count;
   a tie chooses A. Min reduction and comparison are at 0x100b46840 through
   0x100b46948. This is a whole-distribution choice, not per-feature winner
   selection.
3. Selected indices S satisfy nA[i] > 1 AND nB[i] > 1, at 0x100b46990 through
   0x100b469c4. Counts and means select columns using flag bytes 1/0;
   covariance selects both rows and columns using 0/0. Helper 0x100b241a8
   branches on these bytes, and 0x100b2433c through 0x100b2437c explicitly
   loads covariance entries with offset rows * selectedColumn + selectedRow.
4. Selected counts become n[i] = nA[i] + nB[i]. Addition helper 0x100b4f938
   has scalar addition at 0x100b4fa18. Mean expression helper 0x100b4fc44
   reads each operand, multiplies both terms, adds, divides at
   0x100b4fcc0 through 0x100b4fce4:

       m[i] = (mA[i]*nA[i] + mB[i]*nB[i]) / n[i]

5. Three count row vectors (A, B, summed) are repeated across the selected
   dimension at 0x100b46d78, 0x100b46da8 and 0x100b46dd8. Helper
   0x100b500f8 takes a matrix and its transpose and selects the minimum:
   the transposed offset calculation and scalar comparison/store are at
   0x100b50254 through 0x100b5027c. Thus pair weights are:

       NA[i,j] = min(nA[i], nA[j])
       NB[i,j] = min(nB[i], nB[j])
       N[i,j]  = min(nA[i]+nB[i], nA[j]+nB[j])

   N is **not** generally NA+NB. This distinction has an analytic test.
6. Means' self-products use helper 0x100b50500 (left-transpose GEMM is
   separately captured in `../training-followup-20261010/transpose-product.txt`).
   The covariance expression tree in fit-core.txt builds first covariance
   times count-minus-one, adds first mean outer product times count, adds
   second covariance times count-minus-one, adds second mean outer product
   times count, subtracts pooled mean outer product times summed count, and
   divides by summed count-minus-one. Helper 0x100b50e20 scalar instructions
   at 0x100b51060 through 0x100b510cc confirm these operations. The pointers
   loaded from its expression tree map as follows: x27=CA, x25=NA,
   x28=mA outer mA, x16=NA, x1=CB, x3=NB, x26=mB outer mB, x2=NB,
   x0=m outer m, x4=N, x5=N. Scalars from x11/x12/x13 are all 1.

       C[i,j] = ((NA-1)*CA[i,j] + NA*mA[i]*mA[j]
                 + (NB-1)*CB[i,j] + NB*mB[i]*mB[j]
                 - N*m[i]*m[j]) / (N-1)

7. Only S×S covariance and S mean/count entries are overwritten. Indexed
   covariance assignment helper 0x100b4f160 and mean/count replacement calls
   at 0x100b47194/0x100b471a4/0x100b471b4 support this. Other entries retain
   the default input from step 2; no missing-feature imputation is inserted.
8. Boolean true copies A's updateTime. False adds both 32-bit times then
   logically shifts by 1 at 0x100b471b8 through 0x100b471f0. The addition
   wraps before averaging, explicitly tested. The boolean's higher-level
   training meaning is not inferred from its arithmetic effect.

## Implementation limits and validation

`ReferenceGaussianPooling` is an internal comparison-only primitive. It does
not modify acquisition, enable live inference, infer window coordinates or
produce a complete trained profile. Swift finite/nonnegative validation is
an independent support policy. The output is not forced SPD or repaired:
the traced count weighting for unequal feature counts can yield statistics
that require downstream rejection. No such failure becomes mock success.

An empty shared selection is explicitly unsupported until the vendor's empty
indexed-expression and distribution-empty interaction can be compared. It is
not silently treated as a scalar pooled count or unchanged-success result.
Non-vector count matrices are also unsupported. Arithmetic is algebraically
derived; Swift scalar versus BLAS reduction order can differ in low bits.

Validation: `swift test --package-path apple --filter ReferenceGaussianPoolingTests`:
four tests passed, zero failures. Oracles include direct sample covariance
from concatenated sample rows, unequal feature counts with a manually checked
pair denominator, partial masks retaining untouched cells, empty inputs,
minimum-count tie choice, UInt32 time overflow, invalid shape, NaN, negative
counts and nonfinite arithmetic. These are independent analytic oracles,
not Cortex-observed output fixtures. No exact parity claim is made.

No vendor asset is required for this arithmetic. Matched-runtime verification
still needs a trained participant profile and reference stage outputs, which
were not available in the checked local store.
