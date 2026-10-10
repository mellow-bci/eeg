# Detector / mental manager cadence and stop boundaries

Pinned installed arm64 CortexService hash reverified on M4: `cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`. Static LLDB target only, no process attach/execution, vendor assets or trained profiles. Captures: `symbols.txt`, `outer-window.txt`, `window-setter.txt`, `detector-lifecycle.txt`, `reset-rate.txt`. Existing complete manager run body is `../deployed-feature-continuation-20261011/manager-path.txt`.

## Outer delivery differs from inner feature window

`CognitivDetection` constructor at `0x100b26b54` calls the base constructor then at `0x100b26b88/8c` loads both double arguments as 0.125; `0x100b26b94` calls `Detection::setWindowAndStepSize`. `windowSize()` at `0x101234724` reads +0x60 and `stepSize()` at `0x10123472c` reads +0x68. These are outer delivery window/step, not the manager's profile-defined feature window. The outer windows therefore do not overlap at constructor defaults. At 128Hz, each outer block is 16 samples, while the default manager 1-second / 0.125-second recipe accumulates 128 samples and advances 16 samples per epoch.

The constructor also enables `setRandomEEGInterpolation(true)` at `0x100b26ba0`. This is a configuration observation, not recovery or approval of an interpolation implementation. Parent tracing owns upstream delivery and missing-sample behavior. No wall-clock timer or scheduler frequency follows from these sample durations alone.

## One manager removal per detector call

`detect` `0x100b26c58` obtains profile/state then calls manager.run exactly once at `0x100b26c94`; it does not loop over epochs. Ordinary manager body `0x100b2db34..db5c` checks input empty, applies the +0xb38 filter only to nonempty input, appends to MatrixStream, then `0x100b2db94` calls nextWithRemoval exactly once. Empty calls can consume an already buffered epoch; they do not automatically arise from this body. No implicit backlog-draining loop or guessed timer is implemented in our adapter.

At `0x100b2dc50..dc84`, the already consumed epoch skips spectral feature generation if classifier is empty AND manager +0xf0 auto-neutral flag is false AND trainingControl is not 1. Nonempty epochs otherwise enter dataToChannelBandMatrix at `0x100b2dca8`. This distinction matters: our prior diagnostic raw workflow intentionally generated features without a classifier; that remains an explicitly independent diagnostic path. Subsequent sampling/training control invocations can receive empty features; the cadence adapter exposes nil featureInput rather than claiming those controls were skipped.

## Sample-rate propagation and initialization

Detector init calls `Detection::samplingRate` at `0x100b26db0`, sign-extends the returned 32-bit value and passes it to manager.init at `0x100b26dc4`. Manager init requires nonzero profile/rate, stores rate at manager+8 (`0x100b37fa0`), constructs a NEW input filter (`0x100b37d3c..d44`), and constructs/replaces a NEW MatrixStream using that rate plus profile window/step (`0x100b38468..84`). It resets the stream at `0x100b3849c`. No fixed 128Hz is inferred from the base constructor's initial rate for a later configured detector.

## Stop is not a full filter reset

Detector.stop forwards to manager.stop at `0x100b29324`. Manager.stop `0x100b33024` resets existing stream at `0x100b33044`, invokes resetTrainingState at `0x100b33050`, then clears background matrix at +0xb8. It does NOT invoke input filter reset/reconstruction. `resetTrainingState` `0x100b32e88` clears training collections +0x80/+0x98, invalidates elapsed timer +0xd8, zeros sample counter +0xe8 and flags +0xf0, and writes autoSamplingNeutral=0, trainingAction=1, trainingControl=0. It does not touch +0xb38. Reinitialization does replace the filter. This differs deliberately from our raw workflow's independent `resetForGap()` policy.

## Bounded implementation and tests

New `ReferenceManagerCadence` reuses existing input filter and epoch stream kernels, accepts explicit delivered matrix/control state, exposes consumed-but-not-processed epochs and only one removal per call. Stop returns explicit downstream obligations for training/background reset while preserving its owned filter. Init replaces filter/stream. No caller profile mutations, background reset, classifier rebuild, OS scheduling or upstream interpolation are mocked. Malformed calls are rejected atomically as our independent safety policy.

Three authored tests cover explicit backlog ticks, classifier/auto-neutral/training feature gate truth table, stop retaining filter state versus reinit replacing it, and propagated sample-rate window/step counts. No build run in this subtask; parent owns combined verification. No vendor assets needed for these bodies. External parity still needs matching deployed invocation traces and stage outputs.
