# Timestamp search and cross-stream routing

Reference: installed M4 arm64 CortexService SHA256 cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a. Read-only static LLDB function bodies captured in search-bodies.txt and buffer-contract.txt. No symbols-only algorithm assertion, live attach or proprietary trained asset extraction.

## SamplesBuffer::searchSamples

0x10122b37c validates cursor>=0, from>=0, from<=through; initializes SearchResult false/start0/count0 atb3bc..c4. Last retained timestamp must cover through and from atb3e8..41c. Cursor is clamped to retained start atb454..458; scan advances until timestamp>=from, requiring a retained index. If this first sample exceeds through, b4c4..d4 returns complete=true/start=current/count0. Otherwise scan finds first timestamp>=through atb558..580; b594..5a8 includes an equal endpoint and publishes complete/start/count. It is a forward scan, not nearest-neighbor search; cached starts affect search and are not rewound.

ReferenceTimestampSearch preserves these result and inclusion rules on a bounded immutable timestamp array. SamplesBuffer assertTimestamps rejects nonfinite/nonpositive timestamps at0x10122ac20..40 and logs non-increasing timestamps at ac44..48. Our adapter explicitly rejects non-increasing input, rather than emulating invalid logged vendor state. Our memory/index limits and throws are independent support policy. Empty retained buffers return incomplete.

## Clipped fallback

samplesBetweenTimestamps0x10122b5bc starts at retained start, returns empty if tail<from or first timestamp>=from exceeds through. It does not require tail>=through. If tail<through it returns all remaining measured samples; otherwise scans to first timestamp>=through and includes equality atb710..724. No timestamps or voltages are synthesized by this path. ReferenceTimestampSearch.clipped returns selection diagnostics with complete=false; this marker denotes fallback, not a vendor Matrix field.

## SynchronisedSubscription routing

searchData0x10122ca78 skips primary stream atcb48..50; obtains each secondary stream buffer atcb58; searches from cached start atcb5c..cc8 or zero if absent. SearchResult is stored for each stream. A failed result returnsfalse unless permissive flag bit0 is set atcbbc..c4. Ordinary failure does not reach readData slice/cache updates.

readData0x10122c0d8 uses primary cursor/count directly. For secondary complete results it slices start/count atc790..7a0 and caches the **start**, not start+count, atc814..820. Incomplete permitted results call samplesBetweenTimestamps atc534..53c without a cache update. Supplied numeric stream order, retained arrays and primary timestamps are explicit inputs; transport clock production and SamplesBuffer mutation/retention are not guessed.

ReferenceTimestampRouting composes these search/cache/fallback choices. It returns explicit selections for secondary streams; caller retains direct primary slices. Tests feed actual timestamp-search outcomes to ReferenceSubscriptionCadence, then compare timestamp-selected raw blocks through ReferenceRawMentalWorkflow against direct-block diagnostic features. No fitted model, action dispatch or physical EEG assertion is made by authored numerical tests.

## Distinct helpers and remaining boundaries

findClosestTimestamp0x10122b7dc is NOT called by this subscription search path and is not substituted for interval selection. The separate closest helper preserves empty/after-tail(-1) and before-head(-2) timestamp sentinels with index-1; equal head/tail returns retained first. Estimate is trunc((target-first)/(last-first)*count)+start, clamped to retained indices atb874..8ac. Scan direction follows estimate timestamp<=target versus greater; final distance comparison atb954..97c selects the previously scanned candidate on a tie. Thus a forward tie chooses lower, a backward tie chooses upper. Authored irregular timestamp tests cover both directions; no generic nearest-neighbor tie rule is substituted. No resampling, linear interpolation or inferred timebase correction is hidden in timestamp search. Random EEG channel synthesis and packet-gap reconstruction are separate traced layers documented in interpolation-continuation-20261011.

Actual device/host clock characterization, concurrent retained-buffer mutation, timestamp precision/quantization, same-input Cortex output comparison and physical load/sleep/wake qualification remain outstanding. No vendor model assets are needed for this bounded arithmetic and routing.
