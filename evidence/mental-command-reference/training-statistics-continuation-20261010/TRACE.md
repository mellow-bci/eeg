# Accepted feature matrix to Gaussian statistics

`ReferenceTrainingStatistics.fit` reconstructs the ordinary nonempty matrix branch of
`convertTrainingDataToGaussian` (0x100b45f78). Parent captures are archived in
training-input-continuation-20261010; the new coordinate-assignment.txt records
0x100b4ed08..0x100b4f740 from the same pinned binary.

## Contract and arithmetic

- Input X has feature rows and epoch columns. At 0x100b45fb4 the coordinate
  matrix element count is read from +0x10; X rows and columns are read at
  0x100b45fb8/0x100b45fd0. These are independent inputs, not inferred windows.
- Mean expression sets dimension 1 at 0x100b45fe0..0x100b45fe8 and evaluates
  helper 0x100b4cf28 at 0x100b46004. This gives F means over epoch columns.
- Covariance expression at 0x100b46018..0x100b46044 wraps X and passes
  normalization flag zero to 0x100b4d700. That helper at 0x100b4d73c..0x100b4d784
  chooses denominator max(N-1,1) for flag zero; nonzero would use N.
- 0x100b4dab8 evaluates dimension-1 mean (0x100b4db74), then subtracts
  the matching row mean from every epoch (0x100b4dc10..0x100b4dc1c).
  0x100b4d7d0 multiplies the centered matrix by its transpose through
  0x100b4dee4; 0x100b4d914..0x100b4d928 divides by the denominator.
  Therefore C[i,j] = sum_e (X[i,e]-mu[i])(X[j,e]-mu[j])/(N-1).
- Counts are filled with X column count N (0x100b460a0 and stores through
  0x100b46250). Means/counts destination length and covariance destination
  dimensions use the coordinate element count (0x100b46254..0x100b46324).
- Zero-fill helper 0x100b4ed08 uses explicit zero stores or bzero.
  Vector scatter 0x100b4ee3c checks coordinate count equals source element
  count (0x100b4eec0..0x100b4eec8), then assigns source values into ordered
  destination indices (0x100b4ef04..0x100b4ef10). Thus this branch supports
  F supplied coordinates in an F-dimensional destination, not arbitrary wider
  embedding. Unassigned indices remain zero; duplicates overwrite in order.
- Covariance scatter with both flags zero (0x100b46334) visits source columns,
  then source rows and writes destination[selectedRow,selectedColumn]
  (0x100b4f4dc..0x100b4f534). Duplicate coordinate pairs overwrite in that order.
- The three completed outputs are assigned to GaussianData at
  0x100b4634c, 0x100b46358 and 0x100b46364.

## Boundaries and tests

The comparison kernel accepts N>=2 only: covariance's one-column vector
reinterpretation at 0x100b4d744..0x100b4d74c can change feature shape and is
not claimed. F<=70 and a caller-supplied maximumEpochs are explicit independent resource bounds,
not recovered Cortex constants. Nonfinite data/overflow fail explicitly. No
filtering, feature generation, clean-epoch gating or training acceptance is
substituted. Computation order differs from BLAS and bitwise equality is not
claimed. Five analytic tests pass (unbiased covariance, permutation, duplicate
scatter/zeros, constant feature, invalid/nonfinite/unsupported inputs):

`swift test --package-path apple --filter ReferenceTrainingStatisticsTests`

No vendor assets or Cortex output fixtures are added. Exact same-profile numerical
verification still requires observed reference outputs. This code remains outside
the acquisition and production classifier path.
