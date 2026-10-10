# Low-epoch PCA clipping

Reference: CortexService arm64 SHA-256
`cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`.
Static function-body inspection only; no trained vendor assets required.

## Exact finite-domain equations

Let `p` be the pooled mean vector element count and `n[f]` the pooled feature
epoch counts. This is not an overall scalar `N` or a minimum across features.

1. `48690..48694` obtains `p`; `4869c..486ac` copies the original count matrix.
2. `486b0` converts the integer bit pattern loaded into `d8` to floating `p`.
3. `486ec..48714` and scalar tail `4873c..48754` store
   `scratch[f] = min(n[f] - 1, p)`. Vectorized path `48aac..48afc` is identical.
4. `48798..48850` counts **every original entry** with `n[f] <= p` and compares
   that tally with the original matrix element count. Clipping occurs only
   when all original entries pass. Equality is included. One larger count
   bypasses clipping for the entire eigensystem.
5. `48860` loads **scratch[0]**, `48868` subtracts one more, and `4886c` uses
   `fcvtzu` on that value. Within our finite nonnegative conversion domain:
   `endpoint = trunc(scratch[0] - 1)`.
6. `48870..48878` checks endpoint against eigenvalue row count. `4887c` makes
   `retained = endpoint + 1`. `48880..488a0` selects the first `retained` rows
   of the already reversed eigenvalue column, through matrix subview assignment
   helper `1eae0`. `488a4..488cc` checks eigenvector column count and selects
   the first `retained` columns. Input feature rows are preserved.

Thus with finite `n[f] >= 2` and all `n[f] <= p`, retained rank is
`trunc(min(n[0]-1,p)-1)+1`, equivalently `floor(n[0]-1)` in this domain.
It is **not** `min_f n[f]-1`, a numerical eigenvalue threshold, `N-K`, or a
class count. The earlier PCA percentage policy applies after this clipping.

Examples for p=4:

| Counts | Clipped | Retained eigenpairs |
|---|---|---|
| [4,2,3,4] | Yes | First 3 |
| [2,4,3,4] | Yes | First 1 |
| [2,5,3,4] | No | All 4 |
| [3.75,2,3,4] | Yes | First 2 |

## Implementation and limits

`ReferencePCALowEpoch.apply` implements that recipe for finite counts >=2,
1..70 features and finite descending eigenpairs. Count domain and dimension
bound are explicit independent support policies. The clipping primitive
accepts zero/negative finite eigenvalues; it does not invent an SPD constraint
for the vendor clipping body. Our existing decomposition remains separately
strict SPD.

Counts below 2, infinities and NaNs are rejected before conversion. This avoids
pretending a Swift integer conversion reproduces ARM floating-point exception,
negative saturation or NaN behavior. Empty matrices and insufficient row/column
shapes also fail explicitly. No mock success or guessed zero-count rank exists.

Four analytic tests distinguish first-feature control from minimum count,
verify the all-count bypass condition and inclusive endpoint, test fractional
truncation, and reject unsupported conversions or invalid ordering. Trained
profile comparison and singular covariance handling remain separate boundaries.

Reproduce:

```sh
ssh -o BatchMode=yes m4 'lldb -b -o "target create --arch arm64 \"/Applications/EmotivApps/EMOTIV Launcher.app/Contents/MacOS/CortexService\"" -o "disassemble -s 0x100b4868c -e 0x100b488d4" -o "disassemble -s 0x100b48a48 -e 0x100b48b74" -o "disassemble -s 0x100b1eae0 -e 0x100b1ecf0" -o quit'
cd apple
swift test --filter ReferencePCALowEpochTests
```
