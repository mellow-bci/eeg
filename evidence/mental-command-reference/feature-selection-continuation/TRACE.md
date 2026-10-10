# Coordinate selection body reconstruction

Reference: M4 CortexService arm64 SHA256
`cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`.
Static LLDB disassembly only; no vendor process attachment, modifications,
learned profiles or proprietary model assets copied into the deliverable.

The entry/caller body is already in
`training-followup-20261010/selection-neutral.txt`. These captures follow the
arithmetic helpers, not merely their names.

For each class i, feature f, and other class j:

```
eligible[i,f] = count[i,f] >= 20
score[i,j,f] = abs(mean[i,f] - mean[j,f]) /
               (sqrt(covariance[i][f,f]) + epsilon) *
               (eligible[i,f] && eligible[j,f])
score[i,f] = min over j != i of score[i,j,f]
```

`epsilon` is exactly Double bit pattern `0x3ce4000000000000`, loaded into the
expression at 0x100b43e28. This is asymmetric class-i standardization, not a
Fisher score or pooled-variance denominator. The caller gets covariance at
0x100b435a0; helper 0x100b51934 takes the square roots of its diagonal. Helper
0x100b51c14 explicitly performs absolute mean difference, denominator addition,
division, then mask multiplication (0x100b51d2c–0x100b51d50). Helper
0x100b52074 calls 0x100b521a4 with axis0, which reduces each feature column
across the K−1 other classes by minimum (0x100b52234–0x100b5226c).

The eligibility cutoff is inclusive20 in scalar and vector branches
(0x100b43814–0x100b43918). The caller's count matrix is copied unmasked. Sum
reduction helper0x100b5b674, called once for counts and once for the eligibility
matrix at0x100b43b60 and0x100b43b78, sums class rows per feature. The budget is:

```
ratio[f] = sum_i count[i,f] / sum_i eligible[i,f]
budget = min(featureCount, ceil(sqrt(2 * min_f ratio[f])))
```

The numerator includes counts below20. Scalar/vector minimum compares ignore
NaN; positive/zero is infinity. The bounded implementation rejects entirely
ineligible inputs and numeric overflow explicitly. Cutoff/budget evidence is
0x100b43bd0–0x100b43be4 and0x100b44160–0x100b441cc.

Each class is sorted on score row0 descending through SortingTxf(0,1,1),
0x100b44044–0x100b44064. The constructor stores the three arguments at8,12,16;
the comparator uses `gt` when the third argument is nonzero
(0x102142050–0x102142060). Feature indices are carried as the second row and
first budget columns copied at0x100b441d8–0x100b4426c. Helper0x100b5260c/
0x100b52718 flattens, sorts and removes adjacent exact-equal values
(0x100b528b8–0x100b52a04); integer coordinate indices give the union. The
sorting compare/swap bodies use less-than at0x100b52c98 onward, producing
ascending output coordinates.

## Explicit limits

Only one Gaussian distribution per class is supported: the caller checks its
GaussianData vector byte span equals0x220 at0x100b43590–0x100b43598. The
implementation consumes its already fitted means, covariance diagonal and
per-feature counts; it does not invent front-end channel/band coordinates.

The vendor descending sort is not stable. The implementation uses ascending
coordinate index solely to stabilize diagnostics when scores tie. If an equal
score straddles the budget boundary, selection is rejected with
`ambiguousCutoffTie`, rather than pretending its subset matches an untraced
vendor sort permutation. This is a bounded limitation, not exact full-domain
parity. Exact vendor tie-order emulation and actual matched-profile stage
comparison remain unverified.

Analytic tests cover asymmetric normalization, worst-competitor reduction,
inclusive20 eligibility, unmasked budget numerator, class-specific union,
zero-variance epsilon, and explicit invalid/ambiguous rejection.

Reproduction: `cd apple && swift test --filter ReferenceFeatureSelectionTests`.
