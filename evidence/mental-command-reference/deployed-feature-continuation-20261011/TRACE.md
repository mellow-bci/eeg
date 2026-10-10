# Deployed feature/validity continuation, 2026-10-11

Pinned arm64 Cortex binary: cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a. Static disassembly only, no target execution or attach.

## Body-supported contracts

- Manager run 100b2db3c..2db5c applies the stateful input transform at +b38 before appending to MatrixStream. Init 100b37d24..37d44 (prior init-buffer-reset capture) creates FilterTxf mode2 with two three-double lists. Filter recurrence/state must be traced separately; do not substitute a guessed high-pass filter.
- run 100b2dc50..2dc84 skips features only if classifier is empty, training is inactive, control !=1, or the epoch is empty. Empty input does not create a timestamp/feature epoch. An available stream epoch may still be processed on a run with no new input.
- dataToChannelBandMatrix 100b30e80..30f14 orders toArmadillo, preProcessing, Hamming, FFT and channelBandTransform. The current comparison spectral composition still requires preprocessed, selected series; it is not yet a complete raw-device recipe.
- run 100b2dcb0..2dcd0 selects power or ratio with +48. Both Classification wrappers explicitly construct BandRatioTxf mode1. returnBandPowerOnly 10212fa90..12fafc reads metadata columns0/1 as row/band, preserving metadata row order and repeats, and computes 10*log10(P). apply 10212f664..12f7a4 reads metadata columns0/1/2/3 as numerator-row/band and denominator-row/band; mode1 computes 10*log10(Pnum/Pden). Neither body supplies an epsilon/floor. Independent implementation rejects nonpositive, nonfinite or unrepresentable results explicitly, rather than matching vendor NaN/Inf propagation or exceptional integer conversion.
- isCurrentEpochClean 100b312a8..31334 default headset branch takes overallCQ >=50 (constant bits4049000000000000). This is a vendor numeric quality input, not an independently recovered contact-quality decoder. Special Insight and t9/t10 branches remain documented in raw evidence; no untested hardware claim is made.
- run 100b2ddbc onward maintains separate detection and training validity. Only clean, nonempty features enter optional background filtering for training. Detection receives the original feature vector. Noise-detection validity may then change independently in the runDetection overload; that algorithm is not replaced by this contact gate.
- performBackgroundFiltering 100b313a0..3152c initializes background mean to the first feature vector with counter0, then uses old=min(counter,479), newMean=(old*mean+x)/(old+1), counter=old+1, output=x-newMean. Counter saturates480: this becomes exponential smoothing, not a 480-entry rolling buffer. Empty input leaves state untouched. Shape/finite and transactional failure checks are independent support restrictions.
- init reads cognitiv-bands, cognitiv-isBandPower, cognitiv-winSizeInSec and cognitiv-stepSizeInSec from profile. Actual deployed band boundaries, coordinate recipe and values are prerequisites, not invented defaults. run's timestamps use time(NULL), whole wall-clock Unix seconds, not precise acquisition sample time.

## Implemented/tested scope

ReferenceDeployedFeatures tests order/repeated coordinates, ratio dB arithmetic, positive-power failure, all classifier/training/control computation gates and contact threshold. ReferenceTrainingBackground tests initialization, running mean, saturation480, empty/failure/reset state. ReferenceMentalPipeline reuses the power-extraction kernel. Acquisition and independent trainer are unchanged.

## Remaining gate

A matched trained profile and runtime recipe/reference outputs are still required for full deployed numerical comparison. Band recipe and sensitivity values are configuration; learned transform/Gaussian parameters are participant profile data. No vendor binaries, proprietary learned assets or credentials are included here. Offline kernels being tested is not exact Cortex parity, mental-command physiological validation or production readiness.
