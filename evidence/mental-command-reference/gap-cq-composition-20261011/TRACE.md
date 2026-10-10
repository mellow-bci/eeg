# Temporal reconstruction / raw CQ composition

Installed CortexService arm64 SHA256 cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a. This continuation uses complete static bodies already captured in ../interpolation-continuation-20261011; no vendor executable or trained asset is copied.

## Evidence and implemented subset

ReferenceTypeSevenGapReconstruction composes the existing scalar gap kernel with type7/128Hz counter-to-CQ mapping. Raw CQ occupies extracted numeric column7 in the previously traced configuration. Caller supplies the observed counter maximum; the CQ cycle64 is not assumed to be the counter modulus.

- channels-and-packet-gap.txt, 0x101060b10..b3c: modulo counter distance1...65 accepted; duplicates and distances>=66 return an empty reconstruction. This adapter returns inserted=nil on rejection so no loss is concealed.
- 0x101060b48 stores current REAL raw CQ before any generated samples, even when missing=0. cq-reset.txt, storeLastRawCQ/addLastCQ bodies: cache per ordinal; at 0x101060f84 generated samples overwrite CQ-bearing column with cached value. Non-CQ counters retain the scalar interpolated value in that column. Historical cache entries remain; a current counter65 can fill an earlier synthetic counter1, which has the same CQ ordinal. This is an observed reference rule, not a causal quality estimate.
- constructor-time.txt and cache-fill-and-round-table.txt: initial cache entries are positive zero via resize/bzero. They do not mean that physical contacts are good.
- process-routing.txt, 0x1010601a4: one processing call clock read per nonempty batch; 0x101060238..24c: clear EEG history if callNow-lastSuccessfulCallTime >0.5 (strict). This does not clear CQ cache. Empty history passes the current real sample directly, without storeLastRawCQ.
- 0x1010605b0..5b8: only nonempty interpolation result updates previous package; 0x1010606a4: update last successful call time. Empty rejected result leaves history/time unchanged. Constructor call time starts−1.

Our processEEG method models only the type16/type7 value, counter, interpolation-provenance and CQ/history-clock portion. It excludes signal-strength processing, leading timestamp assignment, two uninterpreted integer fields, ancillary arrays and nonEEG routing. It is not integrated into live capture. Measured samples and inserted samples remain explicit; no timestamps, measurements or labels are fabricated.

## Independent policy and tests

Finite values, nonnegative call times, explicit resource limits, atomic state on errors and counter bounds are our support policy, not recovered universal vendor error handling. Existing scalar FMA rules are reused rather than copied into another implementation.

Eight authored tests passed: retained CQ versus linear interpolation, current-before-gap CQ store, maximum admitted distance/wrap, rejected distances, nonfinite/overflow atomicity, strict 0.5 clock reset and cache survival, retained history after rejection, same-clock batch partition/provenance, and an explicit-clock reconstruction → timestamp/history → interval search → spectral diagnostic composition with no fitted model or dispatch. These are software regression checks against body-derived rules, not same-input captured Cortex vectors or physical packet-loss qualification.

No vendor assets are needed for this arithmetic. EPOC X stage order is now traced in ../timestamp-clock-continuation-20261011. Full outer-stage integration, remaining package fields and synchronized real loss/reference outputs remain required before claiming full packet-stage parity or using it in acquisition.
