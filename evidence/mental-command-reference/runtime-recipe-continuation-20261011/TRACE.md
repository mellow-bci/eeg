# Loaded-profile runtime recipe and reset boundaries

Pinned installed CortexService arm64 SHA256 `cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`. Static LLDB bodies only; no target execution, trained profile assets, binaries, credentials or secrets bundled. Captures include complete detector configure/detect/init/stop, manager init/base configure/getters/resetTrainingState, complete parameterSanityCheck single-field body, and concrete failure helpers. The first sanity capture is a partial range; conversion-failure-sanity-full.txt supplies the complete single-field routine.

## Default replacement versus loaded overrides

Detector init `0x100b26cac` obtains actual EmoProfile at26cd4 and reads `cognitiv-version` at26d0c. `QMetaType::isValid`26d4c precedes `QVariant::toString`26d5c and comparison to initialized global version20180327. Invalid QVariant or unequal string enters loadDefaultProfile at26da4..da8. Matching string bypasses default construction. Thus this is whole default construction, not field-by-field merging arbitrary old-version overrides into defaults. Static default construction provenance remains ../deployed-recipe-continuation-20261011.

`ReferenceRuntimeRecipe.ConvertedProfile.version` is already-converted String output or nil for invalid QVariant. The adapter deliberately does not reproduce arbitrary QVariant-toString coercions. Matching-version missing/nonnumeric fields are explicit unsupported comparison errors, not silently substituted platform defaults. Vendor numeric getters call QVariant conversions with null success pointers; arbitrary Qt conversion/missing-key numeric outputs are not proven by the vendor body alone and are not imitated here.

## Recipe getter order and actual field use

`init-profile-getter-order.tsv` indexes actual profile key/getter/conversion call sites in manager init. Initial cache/error settings precede bands; later min/max epochs, maximum Gaussian count, histories/stability/honey follow stream construction. Recipe-specific body:

- bands key0x100b380d8, getMatrix38104. cols38138 must be even; odd branch3813c enters assertion helper102420e80. It copies exactly the first cols linear Matrix elements, iterating38164..17c, not rows*cols. Additional rows therefore do not add band pairs.
- isBandPower key3829c, get382c8, toInt382d4; compare integer exactly1 at38310, cseteq38314/store38318. Integer2 or−1 selects ratio mode; nonzero is not equivalent to true for this field.
- targetChannels38324 supplies channel count to existing generateChannelBandMapping3833c with band count derived from copied edge pairs. Profile eegChannels does not supply this target list.
- window key38370, getter3839c, toDouble383a8; step key383e8, getter38414, toDouble38420. Explicit supplied sampling rate stored manager+8 is supplied to MatrixStream constructor at3846c..47c. No assumed128Hz, no wall-clock scheduler claim.
- timing stream3847c is newly allocated, old stream deleted3848c and new stream reset3849c. Overrides cannot preserve an old epoch buffer through this init.

The bounded adapter requires a nonempty rectangular finite-prefix band Matrix with even column count, typed already-converted integer mode and finite doubles. These finite/resource/error restrictions are our supported domain; vendor empty/negative/malformed coercions are not claimed reproduced. It reuses ReferenceDeployedRecipe feature-coordinate generator/channel dispatch, ReferenceEpochStream arithmetic and ReferenceDeployedFilter state. No new spectral/classifier math or duplicate acquisition path is introduced.

## Channel configuration and filter state

Detector configure26bdc dispatches actual numeric HeadsetType to target list, calls setTargetChan26c2c, tail-calls baseconfigure26c54 with input-channel IDs/profile/state. Base configure1012341b0 scans input list for each target in order and returns false for a missing target. The adapter retains first matching input positions and explicit missing-channel error via existing ReferenceDeployedRecipe. Numeric HeadsetType names and actual live-device ID remain caller provenance.

Manager init37d24..44 allocates a new fixed-coefficient FilterTxf and deletes the old one through its destructor37d48..54. It does not read profile band/timing overrides as filter-design inputs. ReferenceRuntimeRecipe.makeFilter therefore reuses the existing deployed fixed coefficients and creates fresh state. Failure helper102420ea0 has assertion literal `(CHEBY2_HIGHPASS_ORDER + 1) == coeffB.size()`: the actual build names a Cheby2 highpass family/order constraint. This adds no numerical cutoff or sample-rate design parameter evidence.

## Reset and hot-read boundaries

Manager init38ac0 calls resetTrainingState. This clears two feature epoch containers through3649c, invalidates QElapsedTimer32eb4, clears counters32eb8..bc, and explicitly writes profile autoSamplingNeutral=0 (32ef0), trainingAction=1 (32f50), trainingControl=0 (32fb0). It also resets manager background counter at38ab4; full background state math remains its dedicated adapter. A loaded profile's training controls are therefore not simply preserved by this initializer.

Current complete manager run body in ../deployed-feature-continuation-20261011/manager-path.txt rereads crossValidate, rebuildSignature, cache enabled/count and trainingControl on each call. Cache enable uses toInt nonzero (2da6c..94), in contrast to power's ==1. Cache count converts int then sign-extends to unsigned argument at2db18..28; no negative-size support or allocation policy is added by this recipe adapter. The run body does not reread bands/window/step or regenerate channel-band coordinates each invocation. Profile-edit-to-init scheduling outside these bodies is unresolved: accepting a parameter update does not itself prove immediate stream/filter reinitialization. No automatic hot-reset behavior has been invented.

`EmoProfile::getMatrix` failure helper10246ce7c explicitly asserts `v.canConvert<Matrix>()`. Arbitrary profile JSON-to-Matrix conversion, Qt numeric coercion and malformed-profile process behavior remain outside this typed resolver.

## Validation and remaining comparisons

Three independent tests: matching-version multirow band prefix/exact mode predicate/explicit timing; version mismatch whole recipe default and matching missing/wrong converted type errors; fresh stream/filter init state and odd-band rejection. Root coordinates builds; none run by this agent. No acquisition/UI/runtime trainer modifications.

Actual loaded profile and matched reference outputs remain required for Cortex runtime numerical parity, especially learned transforms/Gaussians/priors/sensitivity/neutral handling. Static overrides need no vendor trained assets. No new vendor asset dependency was encountered; none copied. Training/profile activation orchestration, external reinit triggers and current-device hardware enum provenance remain concrete outstanding gates.

## Upstream edit-versus-activation trigger closure

The earlier outside-body gate is now resolved for these two explicit upstream call paths, using root-owned `../upstream-cadence-continuation-20261011/profile-edits.txt` plus the complete sanity bodies above. This does not establish all external callers or asynchronous notifications.

`CognitivDetection::parameterSanityCheck(profile,key,value)` at0x100b293e8 asserts profile nonnull (29414→29f9c→helper102420338) and QVariant valid (29424..38→29fa4→helper1024203bc). Concrete helper strings are `profile` and `data.isValid()`, captured in companion-sanity-assertions.txt. It compares key CASE-SENSITIVELY with exactly `cognitiv-activeActions` and `cognitiv-trainingControl` (29450..88). If neither matches,29490 sets w22=0,29494 branches29ad4,29aec returns x22=0. Therefore bands/window/step/isBandPower edits with a valid QVariant pass the mental-command check; this is not a general recipe-key allowlist, range validator, matrix-type validator or reinit hook. Special active-action/training-control branches remain separate acceptance policy, not reproduced by this recipe resolver.

Upstream updateProfileValues calls this checker at0x100ae9b1c, then NTExpressiv checker atae9b30, ORs both results atae9b34 and rejects nonzero. Companion checker0x100f2f8e8 compares only `ntexpressiv-trainingControl` and `ntexpressiv-trainingExpression` (2f930..960); every other key branches2f964→2fcc4 movw0=0→ret2fcf0. Hence the listed mental-command recipe keys pass both checks, under the validity preconditions. The upstream setter then writes accepted entries with EmoProfile.set atae9c88; there is no stop/init call in this function. Changing stored bands/window/step/isBandPower therefore does not immediately reconstruct the active manager recipe along this call path. Existing run's dynamic reads apply only to its explicitly reread keys as documented above.

By contrast, setTrainingProfile stores the replacement profile/name/action then reads byte+0x4e0 atae9920. If nonzero it calls CognitivDetection.stop atae9930 and init atae9938; if zero it skips that branch. Thus profile activation through this path conditionally reloads the recipe and reconstructs stream/filter/training state. Stored hot edits and activation are concretely different operations; no implicit per-field hot reset is claimed.

This continuation changes evidence only; ReferenceRuntimeRecipe remains an explicit initialization resolver with no hot-edit lifecycle invention. No source/build/vendor asset changes.
