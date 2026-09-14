# Versioned processing settings

Supported tuning has one canonical schema, `eeg.processing-settings.v1`, implemented by
`processing/settings.py`. Current access is `workflow train --settings settings.json`;
the native advanced-settings editor is pending. The app must consume this contract rather
than inventing another set of defaults.

```json
{
  "schema": "eeg.processing-settings.v1",
  "max_training_windows": null,
  "selected_features": 20,
  "pca_components": 8,
  "variance_floor": 0.05,
  "score_threshold": 0.9,
  "margin_threshold": 0.25,
  "persistence_windows": 2
}
```

Omitted supported fields use explicit defaults. Unknown fields or schema versions fail.
The optional training-window budget defaults to no cap. It limits the training array work
when deliberately set; the current dataset loader still holds records in memory, so it
is not an end-to-end process memory limiter. Allocation failure remains a resource failure.
There is no subscription entitlement check or task-class count cap.

Feature selection must fit the current70-feature recipe; PCA components cannot exceed
selected features and are also bounded by available training dimensions. Variance floor
must be positive, score threshold is in(0,1], margin in[0,1], persistence a positive integer.
These are numerical validity checks. They do not establish physiological validity.

Profiles use `eeg.mental-profile.v2` and retain the complete settings snapshot plus the
actual fitted transforms. Inference uses that immutable profile snapshot, not newly
changed global settings. Earlier experimental v1 profiles are rejected explicitly;
retrain from preserved source data with reviewed settings. No real participant model
has been shipped. Threshold tuning after viewing test results consumes that test set as
development data and requires a new untouched evaluation session.

The observed hardware128Hz mode and current256-sample spectral recipe remain separately
versioned and gated. They cannot become supported simply by editing a setting. Changing
that recipe requires matching adapter/feature/native tests and new model validation.
The future native editor should display these distinctions and effective values plainly.
