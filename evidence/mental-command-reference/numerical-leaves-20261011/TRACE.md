# Numerical leaf continuation

Static ARM64 LLDB capture of installed M4 CortexService, pinned SHA256 cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a. No process launch/attach or assets. `leaves.txt` is the initial eight-instruction inspection; `full-leaves.txt` contains complete named-symbol disassembly. Source/tests are comparison-only; no tests/build run by this agent.

## Eigensolver: important audit correction

0x100b5465c is **only a warning printer**: string `warning:` and `given matrix is not symmetric` at5467c/54690, then stream newline. It neither rejects the matrix nor computes eigenvectors. Wrapper48f74 compares method first character d/s (48fb0..bc), warns on symmetry check, and continues. PCA caller48768 passes string `dc` (existing singular-continuation/fitting-callers.txt), so its actual path is divide-and-conquer first.

- Method d calls546a8 at49098; nonzero Boolean succeeds. Failure calls54a64 at490ac. Method s directly calls54a64.
- 546a8 copies the original matrix, sets JOBZ=V/UPLO=U (547e4..f0), calls `wrapper2_dsyevd_` at548c0. Success means INFO==0 (548c4..cc). Fixed double workspace `(4*n+12)*n | 2` =4n²+12n+2 for supported nonoverflowing integer dimensions; integer workspace15n+9 (547f4..54818). No workspace query.
- 54a64 likewise copies original input, V/U, `wrapper2_dsyev_`54c2c; success INFO==0. Workspace3*max(3n,2)−3 (54bb4..bcc). No workspace query.
- Dimension conversion rejects dimensions with bits above signed31 domain. These allocation bounds do not imply practical memory limits; our explicit maximumDimension<=4096 bound is independent safety policy.
- No negative-root clamp or eigenvector sign normalization appears in these leaves. Both use upper triangle; our new leaf deliberately preserves negative roots and LAPACK-produced signs. Existing fitting support policies may still reject negative roots and canonicalize signs.
- Neither wrapper is proof of bit-identical output between vendor LAPACK and Accelerate. Repeated-root bases remain nonunique. Tests compare roots, orthonormality and upper-triangle behavior, not arbitrary vector column signs.

Implemented `ReferenceNumericalLeaves` exposes explicit method, fixed workspace calculator, bounded eigenbasis with original-input fallback, per-attempt INFO provenance. It returns ascending roots and column-major vectors. Failure after both attempts is explicit. Three authored tests cover workspace/resource limits, both actual solvers on upper-triangle/negative-root input, repeated-root subspace invariant and invalid input. The nonconvergence fallback branch is body-supported but no natural nonconvergence fixture has been claimed/tested.

## Inverse leaf identities and actual fallbacks

Dispatcher57690 requires square matrices; dimensions<=4 call579a8. **57fbc is a false return inside that small helper**, not a general inversion leaf. Rejected small formula goes to general588ac through57960..974.

Small 2x2 path57a0c..a4c computes determinant using fnmul/fmadd then requires abs(det)>=2^-52 (bits3cb0000000000000). A smaller determinant does not imply whole inverse failure: dispatcher falls back LU. 3x3/4x4 paths also test that threshold after determinant helper58b88. Full helper/jump-table details are captured but no new small inverse implementation is added.

- 58344: triangular inverse copies input; direction0→U, nonzero→L; DIAG=N (58434..4c); calls `wrapper2_dtrtri_`58474; succeeds iff INFO==0. Successful branch zeros unused triangle via56d5c. Canonical factor inverse algebra remains supported by existing triangular solve; complete scalar low-bit agreement is not claimed.
- 58520: SPD candidate path calls lower-triangle `wrapper2_dpotrf_`587d0, then `wrapper2_dpotri_`587f4 only if first INFO0. Either nonzero fails, permitting general fallback at dispatcher5795c..974. Earlier shape/small special cases also exist.
- 588ac: general LU inverse uses `wrapper2_dgetrf_`58a7c then `wrapper2_dgetri_`58aac, each INFO checked; nonzero factorization fails without inverse call. Work query/allocation handling is captured. This is not pseudoinverse/SVD.
- 580ec handles the small/empty element-count branch and scalar/diagonal special handling with55750; no pseudoinverse label is justified.

No evidence here authorizes successful singular Gaussian densities, variance floors or pseudodeterminants. Runtime final covariance still needs a valid density; fitting scatter retry cannot repair every original class covariance.

## Integration result

ReferenceTrainingEdgeCases.psdEigenbasis now invokes ReferenceNumericalLeaves with divideAndConquer and maximumDimension70. Existing symmetry/PSD rejection, descending order and deterministic sign convention remain explicit independent policies. The shared fitter reaches PCA and classifier rebuild. The reference-focused suite exercises this composition; see timing-motion-offline-20261011/reference-tests.log. A natural dsyevd nonconvergence fixture has not been established, so the fallback branch has body evidence but no empirical failure-trigger comparison.

Remaining numerical gates: scalar wrappers' linked LAPACK implementation/version, full inverse dispatcher matrix-classification/small determinant helper validation and boundary comparisons, matched trained Cortex intermediate outputs, exceptional singleton/count conversion. No vendor assets needed for static leaves or authored tests.
