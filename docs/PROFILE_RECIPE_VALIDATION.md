# Saved-profile recipe consistency

A checksum detects content changes only when compared with a trusted expected
checksum. Anyone can recompute a self-contained profile ID. Consequently the
native `EEGMentalProfile.load` and Python `validate_profile` also check that the
parameters are consistent with the independently declared PCA/diagonal-Gaussian
training recipe.

In addition to existing dimensions, finite values, identities and design checks:

- PCA component rows must be orthonormal: every entry of `components × componentsᵀ`
  differs from the identity matrix by at most `1e-6` in absolute value. Nonfinite
  dot products reject. Relative tolerance is zero. This tolerance is an engineering
  allowance for numerical serialization/decomposition, not a physiological threshold.
- Every Gaussian variance must be at least the profile's configured variance floor.
- Every distance limit must be at least four times the PCA dimension. Both existing
  trainers calculate `max(4 × dimensions, 1.5 × training 99th-percentile distance)`;
  this loader check verifies only the lower bound, not the unavailable training
  quantile or the correctness of the source labels.

Checks reject rather than normalize, repair or rewrite the file. Learned weights,
raw acquisition and the lower-level general scoring kernel are unchanged. A valid
existing v2 profile needs no migration or re-signing; an inconsistent artifact is
not accepted merely because it has a newly recomputed checksum. These checks
apply when loading, opening or saving a profile and when constructing the Python
reference detector. The native detector is normally made from the validated
profile; its lower-level numerical constructor is not a profile-authority API.

Orthonormal rows alone do not establish that they were learned from the claimed
samples. Positive regularized variances do not establish calibration, useful
classification, independent sessions or robustness to artifacts. Training-source
audits and prospective physiological qualification remain separate requirements.
No accepted profile enables control; experimental status remains unchanged.

Reproduction:

```sh
swift test --package-path apple --filter 'MentalProfileTests|ProfileCreationTests|TrainingDatasetTests'
python -m unittest tests.test_mental_processing
```

Malformed synthetic cases deliberately recompute the checksum after scaling a
PCA row, duplicating a component row, dropping variance below the configured floor,
or lowering a distance bound. Original Python and native trained profiles must
still load successfully. These are consistency tests, not vendor-parity evidence.

Checkpoint 2026-09-15: 12 selected native tests and 18 Python mental-processing
tests passed. A fresh native synthetic profile export passed the Python loader
with the same ID and disabled output. All macOS/iOS/visionOS builds succeeded.
No headset session or physiological experiment was performed.
