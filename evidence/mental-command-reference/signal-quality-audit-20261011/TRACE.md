# Signal-quality estimator audit, 2026-10-11

Static arm64 inspection of the installed M4 CortexService; SHA-256 `cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`, verified again in this continuation. No process was launched/attached, proprietary parameter assets read/copied, licensing changed, or hardware exercised. Captures contain bodies and schema labels, not trained model values. Symbols are pointers; conclusions below use instructions in the fresh captures.

## Contact quality is not signal quality

The independent stack has a reference type-7 raw CQ routing/calibration/state/overall recipe (see quality-recipe and quality-routing continuations). This is a measurement of contact-related packet information. The SQ estimator instead consumes filtered EEG windows, spectral features, a learned per-channel Gaussian model and CQ history. Recovering CQ does not imply SQ recovery, and neither is a validated cognitive metric.

`SignalQualityDetection::detect` begins at `0x100c099c4`. It obtains contact quality (`0x100c09a68`), reads minimum CQ per target (`0x100c09b3c`) and calls addCQ (`0x100c09b84`). It high-pass filters (`0x100c09ba0`), transposes and buffers (`0x100c09ba8..09bdc`), gates on a full window (`0x100c09bc0`), computes BandPowerCalculator::transform (`0x100c09c40`), constructs feature rows and analyzes each channel (`0x100c09efc`). SQ overall is calculated separately (`0x100c09fb8`). It is not the raw CQ state calculation.

## Complete small arithmetic recovered

`rootMeanSquare` `0x100c0a3c8..0a4b0` constructs a rows-by-one output, then accumulates each row with `fmadd` at `0x100c0a450`, divides by column count (`0x100c0a470`), square-roots (`0x100c0a474`) and stores. Equation: RMS(x)=sqrt(sum(x[j]^2)/n), with fused multiply-add accumulation. There is no mean subtraction, clipping, n-1 correction or artifact exclusion. Zero columns enter a zero/zero floating operation; the independent helper explicitly rejects fewer than two samples to cover the difference feature too.

The detect feature loop `0x100c09c44..09d9c` constructs differences x[j]-x[j+1], uses RMS of n-1 differences, and max(x)-min(x). Concatenation at `0x100c09dd4,09de4,09df4` adds RMS, RMS difference, range and band-power columns. Parameter names include rms, rms_diff and max_min_diff (`0x100c08f54,08f80,08fac`). The exact band features still depend on the separate transformer/configuration.

`SignalQualityForChannel::analyzeFeatures` `0x100c0f020..0f3e0`: requires one row (`0x100c0f040`), selects configured feature columns (`0x100c0f064`), calls Gaussian logPDF (`0x100c0f0a0`) and requires scalar output (`0x100c0f0a8`). CQ history minimum is reduced from initial4 (`0x100c0f0b4..0f104`). For L=logPDF, L==0 yields transformed score0 and Gaussian state0. Otherwise q=log10(-L) (`0x100c0f12c..0f138`). For three configured thresholds t0,t1,t2, sequential comparisons yield state4 if q<=t0, state3 if q<=t1, state1 if q<=t2, else0. State2 is not emitted by this threshold path. A finite positive L produces a log-domain/NaN path; the new bounded helper rejects this instead of claiming ordinary threshold parity.

RMS thresholds each have length2. Both external and internal amplitude states are0 when RMS<lower,4 when lower<=RMS<=upper,1 above upper (`0x100c0f198..0f204`). `setSMQThresholds` requires two values in each vector (`0x100c0ee1c..0ee34`) and copies them to the corresponding fields.

Let g be Gaussian state, c the CQ-history minimum. Config isSqsCombinedWithCq is read at `0x100c0f214` and `0x100c0f288`. If false, b=min(g,c). If true: c<2 => b=0; c==2 => b=min(g,1); c==4 and g==0 => b=1; otherwise b=min(g,2)+2. Final external/internal states are min(b,the corresponding RMS state) (`0x100c0f26c..0f2e8`). The independent helper takes this Boolean explicitly. CQ ring lifetime/capacity is not invented.

`ReferenceSignalQualityKernel.swift` implements only these finite bounded feature/score/fusion calculations. Gaussian L is a caller input, not a dummy model. Tests are analytic fixtures for arithmetic/boundaries, not Cortex reference outputs, physiological labels or hardware qualification. No build was run by this agent.

## Ordered remaining gates

| Order | Missing piece / exact evidence | Current support and next action |
|---|---|---|
| 1 | Active SQ recipe/model selection. loadParameters `0x100c08c64` reads channels, stepSize, windowSize, smqThresholds and smqInternalThresholds. | Trace the actual configuration loader and hardware/revision selection; no defaults inferred. Need explicit active recipe provenance. |
| 2 | Per-channel trained assets. Channel loader `0x100c0e598` reads selectedFeatures (`0x100c0e604`), multivariateMeans (`0x100c0e66c`), multivariateCovariances (`0x100c0e6d4`), scoreThresholds (`0x100c0e738`), initializes MvnpdfTxf (`0x100c0eb14`). Missing channel parameters produce an explicit error at `0x100c09400..09458`. Flex alone uses ALL key (`0x100c0932c..09340`). | Exact numeric SQ comparison needs these external model values and reference outputs. These are vendor trained/config assets, not recovered by names/body arithmetic. Notify user before inspecting assets; keep them out of deliverable. An independently trained SQ model would be a different recipe requiring its own validation. |
| 3 | Filter recipe and state. Preprocessor::loadParameters `0x100bf1ff8` called `0x100c08f28`; applyHighPassFilter `0x100bf2bc8` called `0x100c09ba0`. | Existing reference filter math is not proof of the exact SQ filter coefficients, reset and sample-rate behavior. Trace these bodies/active parameters then compare impulse/replay outputs. |
| 4 | Window/cadence/CQ history. setWindowAndStepSize `0x1012347e4` at `0x100c08f14`; SamplesBuffer add/isFull/allSamples `0x10122ab10/22a934/22b354`; addCQ `0x100c0e570` calls ring helper `0x100b9d770`. | Need complete buffer shift/window/step unit conversion, CQ ring capacity/reset and stale-history behavior. Supplied windows/history in new kernel are explicit boundaries, not a substitute scheduler. |
| 5 | Exact spectral band transformer. loadParameters `0x100b70f98` at `0x100c08f3c`; transform `0x100b71250` at `0x100c09c40`; band names created `%1_%2Hz` at `0x100c0909c`. | Resolve band limits, FFT length/taper, normalization, units and any logarithms against bodies. Generic FFT/band features already present cannot establish exact SQ recipe. |
| 6 | Parameter column mapping and Gaussian edge semantics. selected-name mapping `0x100c0e880..0eb14`, mandatory RMS check `0x100c0eb84`; logPDF `0x10213fd98`. | Verify exact feature order/duplicate/missing-name and Gaussian singular/error paths using configured synthetic inputs before composing exact estimator. Kernel accepts externally computed L. |
| 7 | Overall/export/lifecycle. detect aggregate `0x100c09fb8` calls calculateCQOverall `0x101f25c38`; values/state serialization and restart remain separate. | Verify SQ external vs internal fields, timestamp/overall channel order, startup/stop/reset and replay determinism. Reuse proven CQ aggregation only after exact SQ caller map verified. |
| 8 | Physical validation. No fresh hardware or SQ reference output collected here. | Compare paired windows and per-channel/overall SQ against Cortex for current qualified EPOC X configuration, including controlled contact loss and artifact trials. Do not label this production-ready or psychologically meaningful. |

## Boundaries

Only new kernel/tests and this new evidence directory changed. Acquisition/decoding, prior docs and UI remain untouched. Capacity/finite-input checks are independent support policies, not recovered Cortex limits. Other headset support remains unqualified. Vendor account/licensing/cloud infrastructure is outside this useful product capability path.
