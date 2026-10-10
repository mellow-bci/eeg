# Type-7 current CQ constructor recipe

Static arm64 LLDB disassembly and constant reads from installed M4 CortexService; no process launched, no vendor profile/model/key read. Binary SHA256 cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a. Existing local-app-analysis captures were pointers only; all cited bodies verified fresh. This adds an offline comparison recipe, not physical contact-transition qualification.

## Configuration and option source

`AbstractInputDevice::setHeadsetConfigFromByteArray` 0x1012417a8..19d0 with type7 takes the supported-type bit in 0x190 and the nonzero first-byte branch. At 18b4..18d8 table 0x102f76090, type−1 index6 is mode7. Input six-byte configuration `01 80 00 10 20 10`, explicit connectionType1: 18ec..1914 combines bytes1/2 little-endian for connection1/type7 → EEG rate128; otherwise that branch uses reversed order. Bytes3,4,5 populate EEG resolution16, motion rate32, motion resolution16. We do not silently apply this interpretation to other connection types/configurations.

`getInputDeviceInfo` 0x101242e94 copies device+0x30 through 0x10000cd34; the scalar tuples at information+0x88..0x98 copy unchanged. `createDataProcessingObject` 0x100fe91d8..91ec loads info+0x88(type),+0x8c(mode) into option+4/+8; 9250..9258 loads info+0x24(revision) into option+c. CQ constructor copies the option to self+0xd8 through 0x101059bac, preserving these fields. Thus type7/mode7/revision0740 can be explicit; no configuration write is required.

`headsetTypeFromVersion` 0x101fc9180 converts revision to hex bytes; the <3-byte branch masks 0xff00. 0x0740→0x0700 at 9304..9318 returns type7. Therefore `initCQThreshold` 68558..68564 does not enter its type5 override path.

## Constructor constants and tuple order

Constructor 0x101067150 onward creates calibration map entries as `(channelID, offset=0, divisor)`, inserts through 0x101069870. Four default threshold doubles at 0x102f6e630 are 0.2,0.7,1.3,1.7, copied to self+0x230..0x248 at 67674..6768c. `isF68RangeGroup` 0x101fca058 is unsigned `(revision−0xf68)<13`; revision0740 false, so normalized interval [1.3,1.7) has state2, not state3.

`getRawEegId` 0x101070d24: type−1 jump table 0x102f6e900 index6=0, mode7/4 branch at d78. Scalar constants 0x102f6e820..84c and 0x10272bca0 construct the raw-index structure. CQ init copies this to self+68..b4; type7 jump table 0x102f6e650 index7=0 chooses14-channel branch. The complete normal map-present path builds CQ ordinal tuples in this order:

| CQ ordinal | Calibration numeric channel ID | Raw EEG column index | Offset | Divisor |
|---|---|---|---|---|
|0|45|0|0|212|
|1|51|1|0|216|
|2|40|2|0|226|
|3|43|3|0|235|
|4|54|4|0|231|
|5|64|5|0|239|
|6|69|6|0|245|
|7|77|8|0|179|
|8|82|9|0|167|
|9|92|10|0|162|
|10|103|11|0|206|
|11|106|12|0|204|
|12|95|13|0|194|
|13|101|14|0|179|

These two numeric namespaces differ. Calibration IDs are map keys, not counter slots or raw columns. Raw column7 is excluded; numeric labels are preserved rather than asserting an unverified electrode-label lookup. Map-absent fallback is not treated as a supported usable calibration.

## Initialization and timing

init 0x10106815c calls QList<double> resize 0x100b5c378. Its grow path calls 0x100089148, which calls bzero at 891ac: remembered raw CQ values start at zero. Separately, init 68188..681d0 assigns per-channel states4. State4 at construction is not an observed good-contact measurement; recalculating zero raw produces state0 and overall0.

Constructor constant0x102f6e620 copied to self+8 contains Int32 128 and90; self+10 is150. In updateCQValues 0x101068ddc..df8 package counter equals self+8 (128) and `(mode|2)==3` skips. **This is not a last-counter or duplicate-counter test.** In current mode7 the mode predicate is false. Package type must be16; eligible counter→slot mapping and remembered raw slots are separate from this recipe. Prior quality-mapping body evidence proves quarter scaling of16-bit non-type5 raw and normalized thresholds; overall uses worst min(3,n) states. No gap reset or physical fresh-contact readiness is inferred here.

## Implementation and acceptance

New internal ReferenceTypeSevenCQRecipe factory supports only revision0740, exact six-byte configuration, explicit connectionType1; these bounds are our support policy. It returns constructor calibration/option diagnostics, distinct initial zero raw and initial state4, and composes the already evidenced numerical mapping. Four analytic tests cover option fields/ordinal table, initial-state distinction, quarter-scale calibrated14-channel overall, and rejection of other configurations. Root owns running tests; no build was run by this subagent. No live acquisition/UI changes.

Remaining gates: compare newly composed CQ states against synchronous reference CQ output, preserve actual remembered-slot timing, and physically test controlled individual sensor contact changes. Electrode display-name lookup, other revisions/configurations/hardware, SQ algorithms and psychological inference are not qualified by this trace. No proprietary trained assets needed for this recovered arithmetic recipe.
