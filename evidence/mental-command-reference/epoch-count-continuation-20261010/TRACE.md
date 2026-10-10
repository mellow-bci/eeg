# Epoch count extraction and Gaussian projection propagation

This closes the index-vector and count propagation questions for finite inputs.
It is static function-body analysis, not matched execution against Cortex.
Capture identities/hashes are in manifest.json. No model assets are involved.

## Threshold extraction is Cartesian, with repeated indices

Existing `../training-followup-20261010/distribution-count.txt` contains the
complete `extractNumEpochsGreaterThan` body. It scans row outer, column inner
(0x100b4c358–0x100b4c3e8). Its source is column-major: the offset at
0x100b4c3dc is sourceRows * column + row. Values equal to the threshold are
excluded by the less-or-equal branch at 0x100b4c3e8.

For each qualifying cell, the routine appends its row to one vector
(0x100b4c3f8, x25) and its column to another (0x100b4c3b0, x27). It does not
deduplicate either. At 0x100b4c6f0/0x100b4c700 these vectors become index
objects. The expression at 0x100b4c710–0x100b4c734 passes BOTH lists, flag
bytes 0/0, to 0x100b241a8.

The helper is captured in `../pooling-continuation-20261010/mask-helpers.txt`
and `additional-paths.txt`. It allocates rowIndexCount × columnIndexCount
(0x100b2430c–0x100b24318), then loops selected columns and selected rows
(0x100b2433c–0x100b2437c), again using rows * selectedColumn + selectedRow.
The resulting matrix is the **Cartesian** submatrix, not the vector of paired
qualifying values. A cross entry may be below the threshold.

Example: [[6,1,8],[2,9,0]], threshold 5, produces row indices [0,0,1],
column indices [0,2,1], and [[6,8,1],[6,8,1],[2,0,9]]. This exact distinction
is tested. Treating this as [6,8,9] would change subsequent fitting counts.

## gaussianTransform takes first column mean and broadcasts

The Gaussian projection body in distribution-count.txt calls extraction with
threshold 5 at 0x100b4961c–0x100b49620. It then builds a mean expression whose
dimension field (+0x20) is zero (sp+0xe0 at 0x100b49628), and invokes helper
0x100b4cf28 at 0x100b49654.

New `mean-helpers.txt` captures that helper and reduction body. The wrapper
loads the dimension at 0x100b4cf48, rejects dim≥2 (the error literal explicitly
states mean dimension must be 0 or 1), and passes it to 0x100b4d038. For dim0,
0x100b4d060–0x100b4d070 allocates one row and the original number of columns;
0x100b4d0d0–0x100b4d13c sums each source column across rows and divides by
the source row count. A nonfinite sum uses a fallback incremental reduction
at 0x100b4d150 onward; our finite-domain kernel rejects such overflow rather
than silently claiming that numerical fallback is reproduced.

The gaussianTransform caller checks nonempty result at 0x100b49678, loads
only its first element at 0x100b49680–0x100b49684, obtains the transformed
mean's element count at 0x100b49690–0x100b49694, fills a 1×dimension row with
that scalar (0x100b4969c onward), and calls setNumOfEpochs at 0x100b498b4.

Therefore, for an input count row vector, projection repeats the **first
count greater than 5 in column order** across every transformed feature. It
does not repeat the minimum, sum or mean of qualifying feature counts.
For a general matrix, the scalar is the first extracted column averaged
across the duplicated selected row list. In the example above it is 14/3;
it can itself be ≤5 because extraction is Cartesian. No physiological
interpretation is inferred for this implementation detail.

No qualifying cells return an empty matrix (0x100b4c78c–0x100b4c794). The
gaussianTransform zero-element result branches to the explicitly captured
Mat::operator index-out-of-bounds exception at 0x100b49968–0x100b49978.
Our kernel instead reports noQualifyingCounts, preserving explicit failure.
Update time propagation is not claimed: gaussianTransform does not call a
time setter in the traced body, and the destination's prior state matters.

## Implementation and validation

`ReferenceEpochCounts.swift` exposes threshold extraction and projected-count
propagation as internal comparison-only primitives. It does not change the
production recipe or manufacture scalar counts for upstream data. Rectangular,
finite, nonnegative count input is our stated support policy. Threshold and
output dimensions must be valid. Empty extraction is observable; projection
of empty extraction fails. Overflows fail rather than applying an unverified
reduction replacement.

Explicit extraction requires the caller's `maximumCartesianCells`; qualifying
count squared is checked for integer overflow and against that capacity before
constructing index vectors/output. This is our resource policy, with no guessed
vendor limit. Projection reduces just the first selected column with the same
row multiplicities, without allocating the Cartesian temporary. A 10,000-count
row test verifies reduction without a 100,000,000-cell allocation. Reduction
addition order can differ from Cortex's paired accumulator but preserves the
derived algebra for finite-domain comparison.

Tests cover duplicate Cartesian indices, strict threshold equality, the first
qualifying row-vector count, general-matrix cross values and below-threshold
reduced output, empty selection, malformed input, negative/NaN counts and
overflow. They are analytic oracles, not vendor-observed predictions.

Validation: `swift test --package-path apple --filter ReferenceEpochCountsTests`
(including explicit capacity and direct-reduction cases): five tests, zero
failures. No vendor-output parity fixture is present.

MANOVA call sites were checked separately in
`../training-followup-20261010/pca-canonical.txt`: combined counts extract >5
at 0x100b49c54–0x100b49c58, zero mean dimension at 0x100b49c60, mean at
0x100b49c98 and first-element read at 0x100b49cc4–0x100b49cc8. Class counts
extract >5 at 0x100b49d94–0x100b49d98, zero dimension at 0x100b49da0,
mean at 0x100b49dc0 and first-element read at 0x100b49df4–0x100b49df8.
These establish the same derived scalar policy for those specific MANOVA
call sites. PCA's broader count flow and other callers remain separate audit
items; do not infer their policy solely from a shared function name.
