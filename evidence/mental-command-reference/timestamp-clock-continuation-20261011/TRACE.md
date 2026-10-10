# Timestamp clock continuation — 2026-10-11

Static LLDB arm64 target CortexService on M4, pinned SHA256
`cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`.
No process launch/attach, model assets, acquisition edits or builds.

## Proven bodies and independent adapter

`bodies.txt`: addFirstTimestamp, syncTimestampAndRealTime, init and round. `round-process.txt`: round static table, processEeg and addTimeStamp. These are function-body findings, not symbol-name inferences.

New `apple/Sources/EEGCore/ReferenceTimestampClock.swift` implements bounded successful-anchor, per-EEG-packet timestamp and explicit synchronization contracts. Callers provide maximum counter, rounding precision, history size, sample rate, prior timestamps and device/motion settings. It does not synthesize a full DataTimeStamp constructor, timer or device qualification.

### Rounding

`Cortex::Core::round`0x101fca7ec:

```
scale = table[precision]
rounded = frinta(time * scale) / scale
```

ARM FRINTA is nearest integer, ties away from zero. Table read at0x102fd6d78 verifies indices0...9:1,10,...,1e9. Adapter supports exactly this inspected range and uses Swift `.toNearestOrAwayFromZero`; it does not assume further table bounds. This is not truncation or ties-to-even.

### Successful initial EEG anchor

`addFirstTimestamp`0x101073da0:

- +0x1a8 false bypasses anchoring. Explicit `anchor` adapter represents only the pending-start true path.
- Scans backward over packages for numeric packetType16 (0x101073df4..e28), selecting the **last EEG package**, not the first packet of the batch.
- If state+0x200 >= suppliedTime, takes reset-flag/log route0x1010740a4; this branch is surfaced as resetRequired, not guessed reset state.
- Successful branch sets cumulative counter distance+0x20c=1, flag+0x220=true, previousCounter+0x208=selected.counter, unrounded EEG time+0x1c0=suppliedTime and+0x218=suppliedTime (e38..e80). Rounds and writes selected.leadingDouble (e84..ed8).
- Clears input list then retains only selected packet (fcc..407c), clears+0x1a8 (408c). No EEG yields numeric error21 at4094. Adapter returns retained original index and rounded time; caller can retain/drop observations explicitly. It does not discard original measurements itself.
- `anchor` doesn't pretend to reproduce opaque flags, unmodeled reset effects, full packet copying or histories. Its state starts with empty history, corresponding to no history insertion in this successful branch; normal subsequent processEeg fills it.

### Counter-driven processEeg

`processEeg`0x101075050:

```
distance = ((counter - previousCounter) % (maximumCounter+1) + (maximumCounter+1)) % (maximumCounter+1)
nextUnrounded = fma(1/suppliedRate, Double(distance), previousUnrounded)
packet.time = round(nextUnrounded, precision)
previousUnrounded = nextUnrounded
previousCounter = counter
cumulativeDistance += distance
```

Exact arithmetic0x101075074..c8. No missing<=64 gate here: that is the separate DataInterpolation kernel. Duplicate counters give distance0 in this function; upstream removeBadCounterSample must not be silently presumed.

When packet+8==0, append `(counter, roundedTimestamp)` to bounded history self+0x1d8; if count>=capacity(+0x1d0), erase one first pair before append (0x1010750cc..138). Nonzero flag skips history but **still advances timestamps/counter**. Negative final timestamp hits assertion path. The adapter preserves this distinction.

### Explicit synchronization

`syncTimestampAndRealTime`0x101074564 receives the EEG/motion pair. Parent process passes self+0x1c0 as pair (earlier interpolation evidence timestamp-stage0x101073470 and0x1010736a4), so changes affect subsequent unrounded clocks.

```
d = realTime - eegTime
if d + (-0.00005) > 0:
    eegTime += 0.0001; motionTime += 0.0001
    consecutivePositive += 1; consecutiveNegative = 0
else if d + 0.00005 < 0:
    eegTime -= 0.0001; motionTime -= 0.0001
    consecutivePositive = 0; consecutiveNegative += 1
else:
    both consecutive counters = 0
if configuredMotionRateField <= 0: motionTime = 0
```

Constants exact bits−0.00005=`bf0a36e2eb1c432d`,0.00005=`3f0a36e2eb1c432d`,±0.0001=`[b/3]f1a36e2eb1c432d` at45b4..648. Boundaries strict. Modes4/7 with motionTime<0 emit warning then **continue correction**, not fatal error (4590..5a8,469c..6ec). Adapter returns warning flag, preserves the behavior. EEG unrounded time<0 asserts at4584/46f0; no negative-time fallback is invented.

### Configuration and adaptive-rate gates

`init`0x101072fcc copies `getCounterMax` to+0x170; `getDefaultSampleRate` results to+0x178/+0x180 and+0x1f0/+0x1f8. It computes+0x1b8 from0.5 for mode6 or64/configurationInt otherwise; additional device-dependent constants+0x168 are in captured body. These fields are not guessed into adapter defaults.

`addTimeStamp`0x10107437c selects initial versus adaptive rate fields depending on its control and elapsed-state comparison at43a4..3c8; numeric type16 calls processEeg at4438, other packets processMotion at4474. Later updates adaptive rates (44d0..528). A fixed128Hz rate is therefore not universally valid. Adapter requires rate per call; this remains an explicit orchestration boundary.

## Validation and limits

Initial five authored tests: rounding including negative ties; last EEG anchoring/reset rejection; counter wrap/duplicates/unrounded accumulation/history flag+capacity; synchronization direction/strict thresholds/motion warnings; atomic invalid-input and counter-overflow rejection. Parent will build/run consolidated suite; this agent ran no build. No live/reference output match claimed.

Own fail-closed policy: finite inputs/outputs, nonnegative EEG clocks, counter domain≤65535, history capacity1...1,000,000, precision0...9, bounded packet lists, uint32 cumulative/correction counter overflow rejected instead of vendor machine wrap. These are declared supported-input limits, not recovered hardware maxima. Errors leave clock state unchanged. Original measurements are never changed by this adapter.

The initial trace left additional orchestration gaps; the continuation below supersedes the constructor, clock-origin, adaptive-rate, hardware-offset and stage-order gaps. Motion timestamp paths, complete reset/history repair, offline processing and real-headset timing comparison remain unresolved. None requires vendor learned assets in the traced bodies. This is not complete DataTimeStamp parity or hardware qualification.


## Continuation: constructor, clock source, rate selection and stage ordering

Static captures: `constructor-process.txt`, `timeutils.txt`, `outer-reset.txt`, `outer-constructor.txt`, `epocx-constructor.txt`, `epocx-methods.txt`, `epocx-init.txt`. No target process was launched or attached. No model/profile assets were accessed.

### Observed constructor values, not implicit live defaults

`DataTimeStamp` constructor0x101072e60 writes decimal precision6 (+0x188;0x101072ef0), history capacity5 (+0x1d0;0x101072f2c), and adaptive transition60.0 seconds (+0x1b0;0x101072f1c). Initial EEG/motion clocks are1.0, cumulative counter distance0, anchor origin−1, pending anchor true. +0x190 and+0x1a0 initially0.1. Adapter exposes the three observed constants only; caller still supplies configuration.

`init`0x101072fcc initializes nominal/adaptive rates from `getDefaultSampleRate`; it derives a lost-time limit0.5 for numeric mode6, otherwise64/configured EEG rate. Hardware offset+0x168 is0.06 for mode6,0.245 for mode10,0.23 for mode9 and0.08 otherwise (including numeric mode7). Mode10 changes warmup+0x1a0 to0. These mode-conditioned constants are evidence, not a claim that all headset configurations have been qualified.

### Clock origin and processing sequence

Constructor obtains `TimeUtils::getEpochNow` and `getCurrSteadyClock`, storing its epoch/steady anchor pair at+0x158/+0x160. `setClock`0x101073300 copies an explicit replacement pair. `getCurrEpochSteady`0x101fca6d8 computes anchoredEpoch+currentSteadySeconds−anchoredSteady. Captured methods quantize via microsecond arithmetic and floating/integer conversions; no simplified implementation of this external clock conversion was added.

`process`0x101073310 returns for empty input or numeric mode11. Positive offline-field+0x228 dispatches `processOfflineData`, not implemented here. Mode10 obtains time from the last type16 packet, otherwise its stored EEG clock. Other modes use the positive supplied argument; nonpositive input obtains epoch-steady time. The upstream origin of an explicitly supplied positive argument remains untraced.

The live branch checks absolute supplied-time minus EEG-clock against the lost-time limit, sets startup/reset flags on excess, records a new origin when pending, then enforces warmup before proceeding. Exact call order is `addFirstTimestamp` → `addTimeStamp` (false control) → `syncTimestampAndRealTime` → `removeBadCounterSample` → `syncHardwareSoftwareTiming`, with error gates. `removeBadCounterSample`0x101074708 checks type16 packet timestamp deviation against the same limit and triggers reset flags; its complete retained-history repair/reconstruction remains outside this adapter. Its name must not be treated as proof of a simple duplicate-counter filter.

### Adaptive-rate arithmetic

`addTimeStamp`0x10107437c compares elapsed=suppliedTime−anchorOrigin against+0x1b0 (0x1010743a4..3c8). Nominal rates are used when elapsed<=transition or the explicit control is set. Otherwise **existing** adaptive rates timestamp the current batch. After that batch, adaptive state updates at0x1010744d0..528:

```
nextEEGRate = Double(cumulativeCounterDistance - 1) / elapsed
nextMotionRate = (nextEEGRate * motionFactor) / configuredEEGRate
motionFactor = numericMode == 9 ? 6.4 : configuredMotionRate
```

6.4 bits are0x401999999999999a. The counter used for the update is the post-batch counter. `rateDecision` is an explicit pure comparison helper returning both current-batch rates and next-batch adaptive values. It does not run a timer, update acquisition, or infer a sample rate. Its finite/positive/bounded-input validation is our fail-closed policy; it is not a recovered vendor recovery branch.

### Hardware offset and original measurements

`syncHardwareSoftwareTiming`0x101074ed0 loops through all packet timestamps. For type16, it first saves the **pre-offset** value to+0x200 (0x101074fb0). It subtracts+0x168 from every packet's leading timestamp (0x101074f1c..24). Thus prior+0x200 means last pre-offset EEG timestamp, not the shifted output timestamp. `hardwareTiming` preserves before/after arrays and returns that last pre-offset EEG value separately. Offset is an explicit input, with no implicit mode7 default. No source measurements are overwritten.

### Proven EPOC X stage order

`EpocXDataProcessing::init`0x1010bcb40 constructs EpocXDataDecryption at+0x178 (0x1010bcba4), EpocXDataValueCorrection at+0x188 (0x1010bcc44), DataInterpolation at+0x198 (0x1010bcce4), DataTimeStamp at+0x1a8 (0x1010bcd84), EpocXDataOutput at+0x1b8 (0x1010bce24). `DataProcessing::process`0x10106dce4 invokes these slots in that order; it forwards its external d0 time argument unchanged to the timestamp stage at0x10106ded0..ded4. This resolves stage identity/order in this binary. It does not implement or qualify complete outer construction, decryption/value correction/output, motion processing, or hardware behavior.

### Additional tests and remaining gates

Two additional authored tests cover the strict60-second transition, previous-versus-next adaptive rates, force-nominal control, mode9 ratio, invalid cumulative count, preservation of pre-offset values, all-packet subtraction, absent EEG and nonfinite offset rejection. Total clock tests:7. Parent owns execution; this agent performed no build.

Remaining: complete startup/reset/history repair and motion/offline paths; caller-selected positive external time source; empirical timestamp agreement and gap behavior on real EPOC X under load/reconnection; full outer-stage integration. No vendor assets are needed for these arithmetic helpers. This is bounded comparison functionality, not complete timestamp subsystem parity or live qualification.
