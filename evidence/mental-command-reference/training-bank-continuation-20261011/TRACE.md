# Training bank and current class weights

Static full named bodies from the pinned ARM64 CortexService are archived in
bank-bodies.txt and conversion-class-weights.txt. They are code evidence, not
execution against a trained profile. No binaries, credentials or learned assets
are included. ReferenceTrainingBank is comparison-only; live acquisition is unchanged.

## addUpdate: first-match append

- 0x100b45c18/45c24: empty training matrix or empty timestamp matrix returns
  without updating the bank (45e68). There is no mock component for empty input.
- 45c30: feature-row count; 45ca4..45cc4: builds indices 0 through F-1.
- 45cdc: converts accepted feature rows / epoch columns to Gaussian statistics
  using those identity coordinates. These are caller-supplied transformed feature
  measurements; this helper does not recover upstream filtering, FFT selection,
  valid-window acceptance or an end-to-end EEG-to-feature recipe. The already implemented ReferenceTrainingStatistics
  reconstructs this converter's ordinary N>=2 branch; see
  ../training-statistics-continuation-20261010/TRACE.md for denominator and scatter evidence.
- 45ce8..45cf4: timestamp first element, FCVTZU w1,d0, setUpdateTime.
  Our supported domain is finite 0...UInt32.max with truncation toward zero.
  Other ARM conversion cases are excluded explicitly rather than fabricated.
- 45d08..45d24: scans class entries in order; first equal classReferenceID wins.
- 45d40..45da4: appends a newly constructed class algebra if no entry matches.
- 45ddc: appends the new GaussianData component. Existing components are neither
  replaced nor pooled in this function. Duplicate class IDs remain separate entries.
- Pooling happens later in combineClassGaussian, independently owned by the
  signature-fitting implementation. addUpdate does not update class priors/weights.

maximumEpochs, maximumClasses and maximumDistributionsPerClass are explicit
independent resource policies, not recovered Cortex defaults. Invalid updates
fail before returning a changed value. Existing bank statistics are preserved as
supplied; this helper neither repairs nor silently refits them.

## getCurrentClassWeights: slot weights, not empirical class frequencies

0x100b35d20 obtains active non-neutral actions. 35d74..35f18 reads all four
cognitiv-action1Threshold through cognitiv-action4Threshold properties as integers.
35f54..35f64 allocates (activeActionCount+1)x1 zero matrix; 35fe0..35fe8 sets
neutral slot 0 to 1. Slots follow threshold1,2,3,4, not arbitrary bank ordering.

Each slot has two branches:

- If manager table length at +0xba0 is exactly 10, index is clamp(threshold-1,0,9)
  and its weight is read from the supplied table at +0xb98. Evidence first slot
  35ff0..36018 and 3603c..3606c; subsequent slots repeat the same arithmetic.
- Otherwise weight = 10^((threshold-5)*0.5). 3601c..36030 explicitly subtracts5,
  multiplies0.5 and calls __exp10; repeats at360b4..360c8,3614c..36160,361dc..361f0.

The function does not normalize these weights and does not calculate sample-count
priors. No table constants or learned asset values are guessed. The helper takes
an explicit table and reproduces selection based on its length. Unknown table
initialization/loading remains a gate. A null profile fails in the reference;
zero-action fallback (35d2c..35d70) is not fully traced and is excluded; >4 active
actions is excluded because this body populates only four action slots.
Table finite/nonnegative checks and overflow rejection are independent support policies.

## Verification boundary

Analytic tests cover Gaussian conversion/composition, preserved components,
first-match class IDs, creation ordering, empty no-op, timestamp truncation,
capacity/shape rejection, neutral/exponential weights and explicit table clamp.
These do not establish same-profile Cortex numerical parity. Matched trained
parameters and stage outputs remain unavailable. No vendor assets are needed
for the traced arithmetic; table values must be supplied explicitly when comparing
that branch, and their origin must be documented without bundling vendor assets.

Validation: `swift test --package-path apple --filter ReferenceTrainingBankTests`:
6 tests executed, zero failures. These are analytical/deterministic tests only.

The manager buildClassifier caller at0x100b2fd38..2fd4c passes feature matrix
(local x29−0x80), timestamp matrix(sp+0xf0), action ID(x22), and local bank
(x29−0xf0) to addUpdate. At0x100b301d4..301e8 it passes that bank and the
manager metadata matrix(+0x28) to GaussianTraining::run. Full manager bodies
are maintained by the lifecycle evidence owner; this confirms the orchestration
boundary without fabricating the feature-buffer/cache construction.
