# Interpolation continuation — 2026-10-11

Scope: static LLDB arm64 target only, CortexService SHA256
`cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`.
No process attached/launched, no trained assets/profile extraction, no live acquisition edits.

## Two different operations

1. `InsightEEGInterpolator::apply` (0x101235e48) synthesizes missing **spatial channels**. It is not a packet-loss repair routine. Its name alone is not hardware qualification; supported caller/device dispatch remains a gate.
2. `DataProcessing::DataInterpolation::interpolate` (0x101060a74) creates missing **temporal samples** between packages. `process` directly calls it at 0x1010603b8 and 0x1010604b4. Full package semantics are not implemented here.

## Spatial kernel

`interpolator.txt` records complete apply, constructor, Detection.configure bodies. Original sample-row/channel-column cells are copied unchanged. Source channel numeric IDs in arithmetic order are `[54,40,72,92,106]`. See the repeated ID lookups in apply (first source40 lookup 0x101235f80). The first sum starts 0x101236220; subsequent sums follow in the complete body.

`decoded-coefficients.json` records all nine rows of exact Double immediate bits and their decimal renderings. These are arithmetic constants in the function body, not recovered trained model files. Each sum uses initial multiply for source54, followed by fused multiply-adds source40,72,92,106 in that order. Output69 copies source72.

`additionalEEGChannels` body and static table read (caller-symbols.txt address0x102f75c68) establish appended order `[45,101,64,82,51,95,43,103,77,69]`; final IDs77/69 are immediate packed constants. No electrode-name mapping is asserted from numeric IDs.

When constructor flag+0x20 is set, each of the ten synthesized cells consumes a separate Qt global random draw, in output order. First jitter branch0x101236298..2d4:

```
u = Double(draw64 >> 11) * 2^-53
factor = ((u * 0.002) - 0.001) + 1
synthesized *= factor
```

The source uses distinct multiply/add instructions for jitter, and fused instructions only for weighted sums. Exact jitter bits are retained in code. `QRandomGenerator64::global`/_fillRange uses shared generator state; its initialization/state/other consumers are **not reproduced**. The adapter requires explicit draws (nil disables jitter) so deterministic comparison cannot silently invent a matching seed. Double rounding can round the maximum factor to1.001.

CognitivDetection constructor enables the flag (previous outer-window evidence0x100b26ba0). `Detection::setRandomEEGInterpolation` merely stores byte+0x70 at0x101234734. This does NOT establish that EPOC X measurements are passed through Insight synthesis. `Detection::configure` captured here does not construct the interpolator. Construction/caller route is still unresolved; no integration into raw mental workflow.

## Packet gap scalar kernel

At0x101060b10..b24, counter distance is modulo(current-previous, maximumCounter+1), and missing=distance-1. `Cortex::Core::modulo`0x101f25e0c implements `((a % b)+b)%b` with signed division. The unsigned conditional at0x101060b28..b3c admits distance1...65; duplicate distance0 and distances>=66 return empty interpolation. A rejected distance is represented by nil in our adapter, not misreported as zero loss.

At0x101060bd4..bf0, delta=(current[j]-previous[j])/(missing+1). For inserted k=1...missing,0x101060c64 uses FMA(delta,k,previous[j]). Endpoint measurements remain separate. The package body also copies an ancillary array at+0x160, fills counters/times, calls CQ helpers, and handles raw-CQ storage. None of those unqualified semantics are manufactured by the scalar adapter. `process-routing.txt` captures the complete parent process for later tracing (two direct calls above).

## Independent implementation and checks

- `apple/Sources/EEGCore/ReferenceEEGInterpolation.swift`: comparison-only pure kernels; sample-major spatial matrix results keep originals and synthetic values separately; gap scalar output excludes both real endpoints.
- `apple/Tests/EEGCoreTests/ReferenceEEGInterpolationTests.swift`: authored basis coefficient checks, explicit draw boundary/order and partition checks, wrap/gap-boundary cases, malformed/nonfinite/resource cases.
- Tests have **not been built/run by this agent**; parent will run the consolidated suite. No claim of live/reference-output validation.
- Our safety policy rejects missing/duplicate source IDs, collision with synthetic IDs, malformed/nonfinite rows, nonfinite generated output, resource-limit breaches, and out-of-range counters. Counter max65535/channel max70 are independent supported-input bounds, not inferred universal hardware maxima.

## Remaining gates / assets

No external vendor assets required for either recovered arithmetic kernel. Full RNG comparison requires observed draw stream or established Qt generator state/order; it is not satisfied by using a new seed. Spatial constructor/hardware dispatch and downstream synthetic channel quality need tracing. Full package interpolation still needs typed timestamp/status/CQ mapping, branch routing, startup/reset/loss-list semantics and hardware comparison. Do not claim this adds Insight hardware support or complete package parity. All live acquisition unchanged.

### Additional package-field trace (not a full package implementation)

The complete interpolation body proves the following field-level operations, without proving names/units for all fields:

- Inserted package+8 is numeric1 (0x101060d90), +0x10 copies DATA_TYPE_INFO+4 (0x101060dd0), +0xc is `(previousCounter+k) % (maximumCounter+1)` using unsigned division (0x101060e14..e2c).
- Previous ancillary values +0x160+8*j are copied, while numeric +0x18+8*j values use the FMA kernel above.
- Two Int32 fields +0x120 and+0x124 receive `previous + k * truncTowardZero((current-previous)/(missing+1))`; integer delta setup0x101060cb0..d0c, cumulative increments0x101060d38..d40, stores0x101060efc/0x101060f44. **These are not asserted to be timestamps.** Prior CQ routing evidence establishes actual package timestamp is leading Double+0; the integer fields require semantic mapping.
- Fields+0x12c and+0x118 copy previous values (0x101060e70/0x101060eb4).
- `addLastCQ` is explicitly called on each generated package at0x101060f84. That helper and constructor/reset state must be traced before claiming whole-package equivalence.

Parent `process` maintains separate accumulated collections, checks packet type+0x10, resets paths, and supplies separate DATA_TYPE_INFO structures to the two interpolate calls. Exact device-mode/data-type applicability is still unresolved in this bounded trace. Consequently adding a fake timestamp/CQ wrapper around proven scalar values would overstate parity; the delivered adapter exposes that boundary rather than guessing field meanings or defaults.

## CQ cache and timing followup (evidence-only; source remains frozen)

New `cq-reset.txt`, `constructor-time.txt` and `timestamp-stage.txt` capture exact bodies. A requested symbol `DataInterpolation::reset` was absent; the LLDB batch stopped there, so constructor was captured in a separate command. This absent symbol is not proof there is no reset behavior.

### Raw CQ persistence

`storeLastRawCQ`0x1010616bc:

- Package type at+0x10 equal32 returns immediately.
- Calls `calculateCqChannelId(headset=self+0x44, sampleRateEnum=self+0xe8, channelCount=self+0x30, counter=package+0xc)` at0x1010616f4. Result−1 returns.
- Calls `isCqInRawData`. True reads Double package+0x18+8*rawCQIndex (self+0x1cc); false reads signedInt32 package+0x138 and converts toDouble.
- Stores at per-channel cache self+0x228 (vector data+0x230, count+0x238), using calculatedCQchannel ID as index. Bounds failure reaches assertion helper; this is not a quality estimate or interpolation.

`addLastCQ`0x1010617b0:

- Package type32 returns. Additionally headset numeric mode9 returns.
- Same counter-based CQchannel ID function;−1 returns.
- Reads cached Double for that channel. For raw-CQ devices writes it back to package+0x18+8*rawCQIndex (0x101061854). Otherwise truncates toward zero toInt32 and writes package+0x138 (0x10106188c..890).
- Crucially `interpolate` stores the **current real package** CQ first (0x101060b48), then calls addLastCQ on synthesized samples (0x101060f84). It does not simply linearly interpolate CQ. Last-value cache entries for channels not present in current observation remain historical.

Constructor getRawEegId(format0) at0x10105feb4 supplies rawCQIndex and mapping. Cache is sized using configured self+0x30 at0x10105ff38..40. Initial cache numeric fill semantics remain unqualified until helper0x100b5c378 is inspected. Existing quality-routing evidence establishes mode7 is raw-CQ and rawCQ column7; helper counter-to-CQchannel mapping is already separately traced there. This followup does not duplicate that source or claim other hardware support.

### Parent reset/routing is based on processing-call clock

`DataInterpolation::process`0x1010600bc:

- Headset mode11 copies input list straight to output (0x101060100..194), bypassing interpolation.
- Empty input skips per-package processing. For nonempty input, calls `getEpochNow()` once at0x1010601a4; d8 retains that same call-time for all packages in batch.
- Numeric packet type16 follows EEG branch (0x10106022c..234). If `callNow-self[+0x210] > 0.5`, clears prior EEG package list self+0x1e0 via helper0x10105b864 (0x101060238..24c); this is not a gap calculated from package+0 timestamp. Empty history appends current measurement directly; otherwise calls interpolate at0x1010603b8 with info self+0x28. Successful nonempty result saves last package and writes callNow to+0x210 (0x1010606a4).
- Non16 branch requires self+0xf0 nonzero (otherwise yields no packet here); analogous callNow−self+0x218 >0.5 clears separate history self+0x1f8 (0x10106046c..480), calls interpolate at0x1010604b4 with info self+0x18. It should not be generalized to arbitrary packet kinds without upstream schema evidence.
- Constructor identifies info self+0x28 as packetType16 and info self+0x18 as packetType32 (0x10105ff14..1c). Their counter maxima come from getCounterMax; numeric channel counts depend on configuration (0x10105fef0..ff34). Both last-call clocks initialize−1 (0x10105fe54..58).

This call clock reset is distinct from detector scheduling and from timestamp assignment; no wall-clock timer is implied.

### Actual leading-Double timestamps belong to DataTimeStamp

`DataTimeStamp::processEeg`0x101075050 proves:

```
distance = modulo(package.counter - state.previousCounter, state.maximumCounter+1)
nextUnroundedTime = fma(1 / suppliedSampleRate, Double(distance), state.previousUnroundedTime)
package.leadingDouble = Cortex::Core::round(nextUnroundedTime, state.roundPrecision)
```

Exact sites0x101075074..b0. It stores unrounded time in state+0x1c0 and counter in+0x208 (b4..bc), adds distance to state+0x20c. A package+8 nonzero skips counter/timestamp history insertion (cc..d0), consistent with synthesized packages carrying+8=1; timestamp computation still occurs. This is an equation/body finding, not a complete timestamp adapter: initialization, rounding helper, startup/offline/clock-correction routes still matter.

Full `DataTimeStamp::process` captured: it invokes addFirstTimestamp at0x101073658, addTimeStamp at0x101073684, syncTimestampAndRealTime at0x1010736ac, syncHardwareSoftwareTiming at0x1010736e0. `processMotion` has additional paths and is captured without inferred semantics. The overall DataProcessing stage assembly/order and EPOC X exact mode flags must be confirmed before composing these into acquisition. Neither DataInterpolation's+0x120/+0x124 integer fields nor its callNow are substitutes for this leading timestamp.

Remaining after followup: cache initial fill; upstream stage order/flags; complete timestamp initialization, rounding and synchronization; numeric nonEEG field meanings; end-to-end injected-loss comparison. No asset dependency surfaced.

### Parent closure: cache initialization and rounding arithmetic

round-and-cache-helper.txt closes the resize helper0x100b5c378: newly grown Double elements delegate to0x100089148, whose tail at0x1000891ac calls bzero on (newCount-oldCount)*8 bytes. Constructor cache starts empty then resizes to configured count (constructor-time.txt0x10105ff38..40); therefore initial entries are +0.0. This qualifies the earlier initial-fill gap, not physical quality/readiness.

Core::round0x101fca7ec loads a table factor at0x102fd6d78+8*precision, multiplies, FRINTA (nearest with ties away from zero), divides by factor. cache-fill-and-round-table.txt confirms table indices0...9 are1,10,...,1e9. No generic decimal/string rounding is substituted. This closes arithmetic and those table entries; actual configured precision, initialization/synchronization branches and supported index bounds remain separate inputs. These constants are code arithmetic, not trained model assets. No new source or runtime integration was introduced by this closure.
