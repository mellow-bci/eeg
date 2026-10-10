# Arithmetic edge continuation

Only new comparison kernels and analytic tests are introduced. No acquisition,
live classifier, existing reference routine, UI or model asset is changed.
Captures use the installed pinned Cortex binary identified in manifest.json.

## Singleton covariance

The ordinary covariance helper at 0x100b4d73c..0x100b4d754 reinterprets a
one-column matrix as a row vector: F-by-1 becomes 1-by-F. Its sample divisor
is max(F-1,1), because normalization flag zero selects the unbiased divisor
(0x100b4d770..0x100b4d784). Thus F=1,N=1 has zero covariance, one mean and
count one, implemented as singletonStatistics. With F>1,N=1 the mean is still
F-by-1 but covariance becomes 1-by-1; the subsequent F-by-F coordinate scatter
requires matching source dimensions (0x100b4f4a4..0x100b4f4bc), so this edge is
rejected rather than silently inventing F zero variances. No vendor-observed
singleton output fixture was available.

## Singular PCA

The existing princomp evidence invokes eig_sym then reverses full roots and
vectors; no positivity check is recovered there. Our singularPCA uses LAPACK
dsyev with deterministic largest-coefficient-positive signs, accepts finite
symmetric PSD covariance including exact zero roots, and explicitly rejects
negative roots. This PSD restriction, exact-symmetry check, F<=70 resource bound
and LAPACK choice are independent support policies, not vendor restrictions.
Repeated-root directions remain non-unique.

runPCA normalizes roots to percentages, cumulatively sums and selects <=99.
The ARM comparison in helper 0x100b541dc..0x100b541e4 uses b.hi to skip values;
unordered NaN also takes that branch (C=1,Z=0). Hence all-zero eigenvalues yield
0/0 percentages and an empty selection, not forced minimum rank. Empty selection
clears PCA basis at 0x100b47e00..0x100b47e18. Positive selection count below K
retains first K-1 columns; count>=K retains found columns. Analytic tests include
singular diagonal covariance, all-zero covariance and a single dominant root.
Low-bit vectorization/eigensolver differences are not exact parity.

## Bounded canonical diagonal additions

The actual failed-Cholesky branch at 0x100b49ea8..0x100b49f3c repeatedly adds
bit-pattern 0x3ddb7cdfd9d7bdbb = 1e-10 to diagonal entries and retries without a
visible attempt bound. boundedCanonical reconstructs that additive arithmetic
using the existing strict canonical fitter, with caller-supplied maximum count.
The explicit 0..10000 budget range is OUR resource policy. It returns the changed
within scatter and exact addition count; exhausting the budget is an explicit
error. Original matrices remain unchanged. Unlike the vendor's unbounded loop,
indefinite or unrepaired scatter can fail finitely. No hidden regularization
or claim of identical singular branch output is introduced.

## Empty shared pooling: partial state, not successful unchanged distribution

Existing combineGaussian evidence copies the input with greater minimum count
before choosing shared indices with both counts>1. With two vendor-nonempty
inputs and no shared indices, indexed covariance assignment has 0-by-0 source
and zero row/column lists; helper 0x100b4f4c0 skips writes. Covariance remains
from the copied base.

However mean/count replacement at 0x100b471a4/0x100b471b4 calls
Cortex::Math::replaceByElementIndex. At 0x10212d538 zero index count branches
to 0x10212d580, which resizes the ENTIRE destination to source dimensions and
copies the empty source (0x10212d588..0x10212d5b0). Therefore mean and count
vectors clear; they do NOT remain from the base. Metadata timestamp still follows
0x100b471b8..0x100b471f0: first timestamp when true, otherwise wrapped32-bit sum
shifted right by one.

GaussianData::getNumOfEpochs returns the matrix at object+0x10. isEmpty at
0x100b41418 first checks that matrix element count at object+0x20; zero elements
returns true at 0x100b41444. Otherwise it reduces maximum count and returns
max(count)<2 at 0x100b41498..0x100b414a0. Both inputs to this edge kernel must
therefore have maximum count>=2. The result is deliberately a separate
EmptySharedPoolingState with empty vectors, retained covariance, timestamp and
isEmpty=true. It cannot be mistaken for a valid Gaussian Distribution. Future
callers must choose explicit empty-state handling rather than mock pooled success.

empty-state.txt also records an unsuccessful lookup for getDimension; no such
function body is claimed. The captured isEmpty body itself is complete.

## Validation and gates

Seven tests passed with:
`swift test --package-path apple --filter ReferenceTrainingEdgeCasesTests`
Oracles check singleton zero variance, PCA generalized eigen-equations and rank
edges, one diagonal addition with analytically known roots, strict no-repair path,
budget exhaustion, empty vector/covariance preservation and timestamp overflow.
These are analytic tests, not same-profile Cortex execution fixtures.

No vendor assets are needed or bundled. Remaining requirements are matched
reference stage outputs and hardware/session-level training validation; these
kernels alone do not establish physiological mental-command accuracy or complete
production readiness. Scalar-versus-BLAS numerical ordering may differ.
