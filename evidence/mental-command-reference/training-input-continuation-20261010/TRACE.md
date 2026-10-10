# Training input continuation: discovered body paths

Static full named captures: convertTrainingDataToGaussian, addUpdate,
isCurrentEpochClean and dataToChannelBandMatrix. Hashes in manifest.json.
These functions are traced evidence, not newly implemented acquisition paths.

convertTrainingDataToGaussian (0x100b45f78) converts Math::Matrix to Armadillo,
checks dimensions versus selected indices, resets GaussianData, then invokes
mean helper 0x100b4cf28 with axis1 (0x100b45fe0–0x100b46004). It creates a
transpose expression before covariance helper 0x100b4d700 (0x100b46018–44).
It broadcasts original column count into a count row and indexes means/counts
and covariance before setNumOfEpochs, setCovariance and setAverage
(0x100b46344–64). Full covariance normalization and conversion storage semantics
must be followed before treating this as a production sample accumulator.

isCurrentEpochClean (0x100b30fec) has different headset branches: isInsight,
numeric headset types9/10, and the remaining branch. The remaining branch
reads ContactQuality::overallCQ and compares it inclusively to 50 (Double
bits0x4049000000000000, 0x100b31328–34). This is a vendor quality gate, not a
physiological artifact detector. Mapping headset enums, the overallCQ formula,
and the caller's final validity predicate remain necessary before routing our
EPOC X data through that gate. Native raw contact values must not be mistaken
for this derived scalar. No quality rule is silently installed from this trace.

The named dataToChannelBandMatrix converts the matrix and calls
Classification::channelBandTransform at0x100b30f14 with explicit sample-rate
and band-vector arguments. This confirms argument flow; it does not establish
the actual deployment's window, hop, channels, feature mode or band parameters.

No trained model asset is encountered in these bodies. Actual learned training
state and observed reference outputs remain needed for matched comparison.

Covariance helpers are additionally captured over addresses
0x100b4d700..0x100b4ed08. At0x100b4d76c..84 the helper chooses N for
nonzero normalization mode and max(N−1,1) for zero; the caller passes zero.
This establishes the divisor branch, not every mean-centering/reduction or
original matrix orientation contract. The capture is bounded by addresses;
external calls require separate evidence before a complete accumulator claim.
