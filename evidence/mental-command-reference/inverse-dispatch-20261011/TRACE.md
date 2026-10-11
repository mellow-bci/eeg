# Inverse dispatch and boundary continuation

Evidence is the actual complete dispatcher and leaf bodies in the pinned installed CortexService capture `../numerical-leaves-20261011/full-leaves.txt`, not README inference. `dispatcher.txt` is an exact excerpt; `source.json` identifies its source hash and binary. No vendor profile, weights or credentials required.

## Recovered finite-matrix route

`0x100b57690` rejects nonsquare matrices. Sizes ≤4 go to `579a8` before any triangle/diagonal checks; failed small formula falls directly to LU `588ac`. A triangular 2×2 matrix therefore does not take `dtrtri` through this dispatcher.

For n>4, `57708..57764` tests exact zero off-diagonal values and chooses the diagonal inverse helper `580ec`. `5776c..5794c` cheaply probes then fully checks upper and lower triangles, choosing `58344` with direction0 upper/direction1 lower. Simplified whole-triangle predicates preserve finite-input behavior; the original cheap probes change only traversal cost. Negative zero compares equal to zero; tiny nonzero entries remain nonzero.

Remaining dense matrices enter the SPD **heuristic** at `577cc`:
- Every diagonal strictly positive; largest diagonal accumulated (`577dc..7fc`).
- Each lower off-diagonal magnitude strictly less than largest diagonal (`57854..60`).
- Symmetry accepts absolute difference ≤ bit-pattern `0x3d19000000000000`, OR difference ≤ max(abs(lower),abs(upper)) × that constant (`57864..90`). This is a combined absolute/relative tolerance, not exact equality.
- Twice lower magnitude strictly less than the sum of the corresponding diagonal entries (`57894..8a4`).
- Passing the heuristic calls `58520` (Cholesky inverse). Failure still falls to general LU (`5795c..74`). Pairwise conditions do not prove positive definiteness.

`ReferenceInverseDispatch.route` covers this classification for finite bounded matrices. Its route is consumed by `inverse`, which implements scalar1, small2/3, diagonal, triangular, SPD and LU fallback. All dimensions within the explicit resource bound now have an implemented route, including the 4×4 scalar shortcut. This is still reconstructed behavior rather than oracle-verified numerical parity. Nonfinite/zero-sized/resource rejection are explicit independent policies.

## Small determinant boundary

`57a14..18` evaluates `a*d + (-(c*b))` using fused multiply-add after a rounded negative product. `57a20..2c` rejects only `abs(det) < 2^-52`; equality (also negative determinant with equal magnitude) is accepted. Rejection means try LU, not declare singular. `smallTwoByTwo` returns nil to preserve this meaning. Overflow/nonfinite output throws as an independent wrapper policy; vendor shortcut has no equivalent finite-output guard.

## Triangular inverse leaf

`58344..58474` copies input and calls `dtrtri` with direction U/L and non-unit diagonal N. INFO0 succeeds; the unused triangle is then cleared by `56d5c`. `triangularInverse` uses platform LAPACK and explicitly clears that triangle. It can serve callers that already know a triangular factor, but bypassing n≤4 shortcut dispatch must be disclosed as an algebraic alternative, not exact scalar parity.

## Validation and remaining gates

Nine authored tests check dispatcher precedence/exact zero; strict magnitude/pair thresholds; absolute/relative tolerance boundaries; an indefinite matrix that passes the SPD heuristic; signed inclusive 2^-52 boundary and nonsingular shortcut rejection; triangular leaf orientation, unused triangle clearing, and singular rejection. These tests compare reconstructed behavior and mathematical invariants, not a running Cortex oracle.

Still required: actual trained-profile intermediate comparisons; vendor-linked LAPACK agreement; independent Cortex output comparisons at ill-conditioned scalar boundaries; overflow/nonfinite vendor behavior (intentionally excluded). No exact end-to-end numerical parity claim follows from these tests.

## Executed composition and additional body trace

`inverse` preserves original input for SPD→LU fallback. LU follows `588ac`: workspace max(n,16); only n>16 performs dgetri workspace query before dgetrf; query INFO, factor INFO and inverse INFO checked. Our query allocation cap16,777,216 doubles and finite output guard are independent resource policy. Accelerate may differ from vendor-linked LAPACK.

Fresh `spd-mirror.txt` disassembly confirms the post-dpotri helper is symmatl/symmatu copying (`58d64`); lower-to-upper is used by this caller. Fresh `small-determinant.txt` captures `58b88` and statically reads residual tolerance1e-10 at0x102648168. The n3 expansion at58bd4..c14 is implemented with original product/FMA ordering. Cofactors57fc4..580a8 are followed by first-row/first-inverse-column dot at580ac..c0; success requires strict abs(1-dot)<1e-10. Small shortcut rejection goes to LU.

n4 is implemented in `ReferenceSmallFourInverse`: determinant58c18..58d28 and cofactor57a78..57f74 use address-annotated register slots to retain scalar rounded products and FMA ordering. Its final dot57f78..98 shares the residual gate580c4..d8. Forty nonsymmetric conditioned authored matrices pass inverse-identity residual tests; determinant threshold equality/nextDown exercise shortcut/fallback. No ill-conditioned matched Cortex oracle has been acquired.

Canonical caller method is independently confirmed in `../training-followup-20261010/pca-canonical.txt`:4a128..12c loads `dc`,4a140 invokes48f74. Root owns integration of that correction in ReferenceCanonicalTraining.

## Test execution

`swift test --package-path /tmp/eeg-inverse-standalone` ran an isolated Swift6 package containing exact copies of the two new source files and the new test file:9 tests,0 failures. This avoided concurrently edited unrelated test sources in the shared package. `validation.json` records source hashes. Root performs the full package integration suite. Platform deprecation warnings for legacy Accelerate LAPACK C entrypoints are visible in the log.

Root integration: ReferenceCanonicalTraining now consumes this inverse dispatcher for its lower Cholesky factor and the shared dc eigensolver. Generalized-eigen residual tests exercise dimensions3,4,5. This replaces the old independent scalar inverse loop while preserving declared lower-factor/Cholesky/final-solve choices.
