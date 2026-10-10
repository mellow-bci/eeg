# Spectral follow-up, 2026-10-10

Source: M4 installed arm64 CortexService, SHA256 cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a. Static LLDB target only; no vendor executable launched by these traces. Captures contain disassembly, not bundled binaries or learned assets. SHA256SUMS identifies captures.

## Implemented bounded arithmetic

`ReferenceSpectralPipeline.spectrum` accepts one already-preprocessed series, power-of-two N>=2. Independent radix-2 FFT; not a port of vendor FFT implementation. Classifier selects FFT_Txf(2,true). FFT arma apply 0x102131410 checks length, retains N/2 bins (Nyquist excluded), transposes and normalizes by N. Classification wrapper multiplies complex values by (2,0); Complex2Real mode0 at 0x1021300dc computes squared magnitude. Result is 4|DFT(x)/N|². Forward versus inverse sign does not alter these real-input powers. Vendor butterfly helper 0x102132060 is captured; floating operation order differs.

`bands` corresponds to channelBandTransform mode0. Constructor 0x10212dca8 stores sample rate and pairs of frequency boundaries. Apply 0x10212e54c computes spacing sampleRate/(2*binCount); lower=ceil(lowerHz/spacing), upper=min(lastBin,ceil(upperHz/spacing)), both inclusive. Sum at 0x10212e918 uses separate even/odd accumulators. Jump table at 0x102ffdfc7 has bytes 00 0e 00 1e: mode0 branches to 0x10212eb3c, which DIVIDES by inclusive bin count. The classifier wrapper doubles the result. Therefore mode0 is twice the mean, not twice the sum. Adjacent intervals can overlap; no conventional half-open substitution.

Own API restrictions reject nonfinite data, empty/out-of-range intervals and non-power-of-two series rather than reproducing vendor assertions. Units are squared input units; this is not presented as calibrated PSD/Hz.

## Not resolved or activated

Preprocessing reduces a matrix by median, not mean. Its channel/time orientation and caller channel selection need closure before exposing raw-EEG entry. `dataToChannelBandMatrix` 0x100b30e80 calls preprocessing, Hamming, FFT, channel-band in that order. Actual channel-band feature mapping, band-ratio mode selection, window length/hop, sample rate configuration and selected feature indices remain required recipe inputs. `bandPowerTransform` delegates to BandRatioTxf::returnBandPowerOnly; flattening must not be guessed.

These kernels are internal, offline-test-only and do not alter existing independent mental-command profiles. Tests use mathematical fixtures; none is an executed Cortex comparison.
