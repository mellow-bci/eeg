# CQ packet routing, remembered slots, batch output and detection

Fresh static arm64 disassembly from installed M4 CortexService. Pinned SHA256 cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a. No execution, acquisition, profiles, models or keys accessed. Existing captures used only as pointers. All functions below freshly captured.

## Raw extraction and packet gate

updateCQValues 0x101068cc0 copies each ExtractedPackage, then 68dd0 accepts only numeric packetType16. Counter at 68ddc is compared against constructor self+8=128; if equal and `(mode|2)==3`, skip. Thus mode1/3 reject counter128; current mode7 does not. This is not a duplicate-counter detector.

calculateCqChannelId 0x101f25dc4..25e08 computes signed truncating remainder `counter % trunc(sampleRate/2)`; type2 accepts remainder divisible by4 and then divides by4. It returns −1 if resulting slot is not less than configured channel count. Our only executable routing support is type7/rate128/count14, nonnegative Int32 counter: slot=counter%64 and slots0..13 accepted. Negative counters, zero rates and other hardware tuples are not silently generalized.

isCqInRawData 0x1010714a0 tests bit(type−1) in 0x14d for types1..10. Type7 is true. At 68e40..e50 it reads the extracted numeric array using configured raw-index field self+a4 and array offset0x18; current getRawEegId mode7 field+a4 resolves raw column7. Other hardware reads ExtractedPackage+0x138; that path is evidence only. This adapter takes an explicitly extracted rawCQ observation; it does not claim to implement numeric-package layout or decoding.

## Persistent storage and scaling

68e84 assigns only the routed remembered slot. 68ee8..68f4c calls isEeg16Bit(revision,mode) and quarter-scales that newly assigned slot for16-bit non-type5. Crucially, unchanged slots are already scaled and must not be quarter-scaled again on subsequent batches. The adapter retains original raw and remembered mapped values separately. Its process snapshots use mapped values directly when normalizing. Ineligible packages/counters leave previous slots intact. No gap-based clearing or timeout is present in this body; our replay does not invent one.

## Batch boundaries and rows

DataOutputContactQuality::process 0x101068c24..68cbc calls updateCQValues once for the full list, then updateCQStates once, then calculateCQOverall. EpocXDataOutput::process 0x1010b7d54..7da8 passes its extracted EEG package batch through this process then makeCQ. Therefore the wrapper emits **the final batch state map and final overall on every row of that same batch**, not a progressively changing state snapshot per input packet.

makeCQ 0x1010b9434..9f14 uses the incoming package count to allocate output. Each row timestamp is its ExtractedPackage leading double at 9594..95c4. Map lookups for channel positions1..14 use stored raw-ID structure set by constructor at 7888..78a4, sourced from getRawEegId(format0); current mode7 yields the same raw indices as previously traced format3. Map keys are raw EEG column indices, not constructor calibration numeric IDs. Timestamp is output column0; overall passed in d0 remains d8 and is written in output column15 at 955c (x27=15*n built 9520..953c). Map-absent paths use state0; unsupported missing mapping is not fabricated by our supported recipe. Detection display/schema IDs remain explicit adapter input; their surrounding DeviceData channel metadata path is not inferred from calibration IDs.

Our Batch returns timestamp/state/overall arrays (column semantics preserved without pretending to own a DeviceData layout). Every state row is the batch-final14 states. Output memory bound maximumPackets is an explicit independent support policy; supplied batch boundary is meaningful for reference comparison.

## Detection ingestion

DetectionCore::ContactQuality::set 0x101232938 calls clear, returns empty if matrix empty. For nonempty input 32980 sets global minimum4 and 3299c..329b0 prepopulates each supplied numeric channel epoch minimum4. Clear at 326b0..327a4 empties maps and zeroes minimum/overall/timestamp.

Special channel exclusion bitmask0x20043 over `(id−146)` skips IDs146,147,152,163. ID147 on the final row sets overall+self18 at32a48..32a64. ID152 on final row sets timestamp+self20 at32a6c..32a88. Other channel values truncate Double toward zero via fcvtzs, then assert class0..4. Final row class values populate the last-state map at32ab8..32acc. All ordinary rows reduce global minimum at32ad4..32ae0 and per-channel minima at32af0..32b70. No conflation of last state, epoch minimum, and overall is warranted.

New explicit-channel detection adapter requires unique channel IDs, finite rectangular rows, <=32 columns, bounded rows; these are our support policies. It preserves initial4 for excluded special IDs in the epoch map. IDs147/152 take final-row scalar values only. Empty matrix returns empty zero state. Tests supply explicit channel schema, not a guessed device metadata order.

## New code and tests

ReferenceContactQualityRouting.swift: packet gate predicate, bounded current counter route, remembered original/mapped slots, batch-final output composition and explicit numeric-channel detection matrix adapter. Five analytic tests cover gating/remainder boundaries, same-slot overwrite and batch broadcast,14-channel routing→mapping→overall→detection, epoch minimum vs last state, size/invalid-data failure. Atomic validation of used observations is our own adapter policy; vendor ErrorUtils exceptions are not reproduced. No builds performed by subagent; root runs tests.

Remaining: reference outputs with exact extracted batch boundaries, raw numeric/package adapter integration, DeviceData channel-schema metadata verification, controlled physical sensor-contact changes and observation freshness rules. SQ remains separate and unimplemented here. Other headset tuples are discovered, not supported/hardware-qualified. No vendor trained model assets are needed for this arithmetic CQ subset.
