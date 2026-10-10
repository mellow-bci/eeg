# Raw and overall contact-quality continuation

Pinned M4 arm64 CortexService SHA-256: `cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`. Static LLDB only; no target launch/attach. Three new captures include function bodies and the non-secret 11-byte isEeg16Bit branch table. No vendor profile/model assets, keys or recordings copied.

## Existing verified and unresolved scope

Our Decoder retains raw ADC word7. Existing CONTACT_QUALITY.md reports same-sample Cortex raw-word agreement (3,845 and 15,361 matched samples), tracker slot routing for the documented revision0740/config018000102010, and unresolved classified contact transitions. Those hardware claims are not expanded by this static trace; screenshot firmware0730 is not automatically qualified by revision0740 evidence. Existing Python/offline tracker and live capture are unchanged.

## Raw word to state: proven bodies

DataOutputContactQuality::process (101068c24) orders updateCQValues → updateCQStates → calculateCQOverall; ErrorUtils::isBug gates subsequent stages. No error is converted into mock quality success here.

updateCQValues (101068cc0) iterates extracted packages and only processes packet-type numeric16; its mode/counter gate at68dd0–68df8 can skip packets. Slot routing calls calculateCqChannelId at68e08, with stored headset type, sample rate, configured channel count and packet counter. Existing routing body (local-app-analysis/cq-routing.txt) computes counter remainder by sampleRate/2, checks configured channel count, and has a separate type2 adjustment. For type7 with128Hz this matches counter%64; other rates/types are not silently assumed.

The isCqInRawData branch reads extracted numeric array at configured raw index+a4 and offset0x18 (68e40–68e84); other hardware reads packet field0x138. The value is stored in persistent per-slot list at+208: unupdated slots remain remembered. There is no explicit per-sample channel-state smoothing inside this body.

**Additional upstream scaling:** at68ee8 it calls isEeg16Bit(version,mode). If true and headset type!=5, it multiplies the stored slot value by0.25 (68ef0–68f4c). This must precede the state normalization. isEeg16Bit at101fca16c dispatches by headsetTypeFromVersion; the captured table at102fd6d1a is `[0,9,0,2,6,9,2,9,0,9,9]`, jump base101fca1ac. For numeric type7, offset2 enters mode==7 or mode==4 comparison. Our adapter takes the resolved boolean explicitly; it does not invent the hardware mode from an unrelated field.

updateCQStates (1010690bc) checks remembered-value count against mapping count, error34 on mismatch. For each slot it reads mapping tuple `(channelID, Int32 offset, Int32 divisor)` and computes:

`z = (storedValue - offset) / divisor`.

Comparisons use four thresholds at object+230/+238/+240/+248 (691e8–69244). For finite values: below t0→0; [t0,t1)→1; [t1,t2)→2; [t2,t3)→3 if isF68RangeGroup(version) is true, otherwise→2; >=t3→4. Equality advances to the next interval. The fourth interval does **not** universally mean3. Existing default-threshold evidence contains0.2,0.7,1.3,1.7 and constructor divisors, but these remain hardware/configuration inputs; no raw-to-ready default is enabled. NaN/divisor-zero behavior is not matched by our bounded adapter.

## Overall quality is worst three

DataOutput calculateCQOverall at101069374 obtains QMap values; non-Flex path passes all values to Core calculateCQOverall (69498–694c0). Flex has a configured-channel subset path; no Flex support is asserted.

Core calculateCQOverall (101f25c38): k=min(numberOfStates,3); empty returns0; sort integer states ascending; sum firstk; return `100 * sum / (4*k)` (25d88–25da0). The sort helper266a4 is captured through26ec0. For the14-electrode case, insertion branch26bec/26c28–26c54 shifts a larger predecessor right when next is smaller, proving ascending/worst-first ordering. Two-element branch26b34–26b48 likewise swaps when final value is smaller. Thus a single poor electrode affects the worst-three aggregate rather than being diluted over all14.

Example supplied states `[4,4,0,1,2,4]` yield25, not62.5. All4 yields100. Numeric0…4 are contact classes; the aggregate is not a psychological score or artifact-free EEG guarantee.

## Output to detector/mental-command manager

EpocXDataOutput::makeCQ at1010b9434–b9f18 copies current QMap numeric states into the output numeric list together with supplied overall/time fields; full body now captured (earlier partial capture stopped midfunction). This is packaging of already-classified CQ, not an independent EEG-quality model.

DetectionCore::ContactQuality::set(Matrix,ChannelList) at101232938 resets state, iterates rows and listed metadata channels. Numeric channel0x93 copies final-row overall into object+18 (232a48–232a64); numeric0x98 copies final-row timestamp into+20. Ordinary channel values are converted via fcvtzs and checked to be in0…4, updating per-channel minima across rows and last-row state. overallCQ getter232928 returns+18. Therefore manager overallContactQuality input derives from the final-row supplied aggregate, whereas epoch channel minima are separate fields; do not recompute overall from epoch minima and call it the same value.

Prior deployed-feature trace proves isCurrentEpochClean default headset branch compares that overallCQ against50. This stage does not itself decode raw CQ and does not substitute SQ.

## CQ versus SQ and implementation boundary

Contact quality is the device/raw-value classification described above. Signal-quality processing is separately named in PerformanceMetricsV2 SignalQualityDetection/SignalQualityForChannel and DetectionCore CQSummary::initForSQS; their function names alone are not algorithm evidence. Existing good-quality screenshot cannot prove our raw signal is physiologically valid or artifact-free. No SQ classifier/model is implemented in this continuation.

Added NEW internal comparison-only ReferenceContactQualityMapping and five analytic test methods: explicit resolution scaling, threshold boundaries/F68 branch, worst-three aggregate, malformed-input/bounds rejection, plus a composed14-channel analytic snapshot retaining raw/mapped/normalized/state diagnostics. Added explicit type7 mode4/7 resolution predicate supported by the captured jump table; it does not parse device configuration or claim hardware qualification. Caller supplies resolved configuration. Finite input, positive divisor, strictly increasing finite thresholds,0…4 states and explicit allocation bound are our support policies, not recovered vendor validation. No test was run by this subagent per root build ownership; root will report consolidated results.

## Remaining gates and asset needs

To enable live classified CQ, resolve and qualify exact firmware/headset mode, raw-array extraction units, constructor mapping for that configuration, initialization/default remembered values, packet-type/counter/mode skip timing and contact-state transition alignment against the physical headset/Cortex. The longer reference previously showed the same raw value associated with different subsequent classes; this trace identifies stored-value/scaling/gates but does not prove that timing discrepancy resolved.

No vendor trained-model asset is required by the shown arithmetic CQ path. Configuration/calibration inputs are required and must be read/traced for our physically verified configuration; do not treat old divisor tables as universal assets. SQ and performance metric internals remain a separate analysis/validation task and could have learned/configured dependencies not resolved here. Hardware experiments with controlled electrode contact changes are still needed before readiness integration.

Configuration source follow-up: older initCQThreshold body6855c–68564 only enters the configured CQ-threshold override path for numeric type5; type7 returns at68b8c without that override. Thus its constructor threshold initialization remains the relevant source. Constructor raw mapping/default threshold captures are in local-app-analysis/cq-constructor-raw.txt/cq-constants.txt; resolving current option tuple selection and physically matching transition timing remains open. This continuation deliberately requires explicit tuples rather than embedding old per-electrode divisors as a universal live default.
