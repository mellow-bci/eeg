# Consistent settings during native dataset preparation

The reviewed-recording dataset builder previously called `EEGTrialDatasetExport`
without a settings argument. Its canonical loader consequently used default
settings, including an unlimited training-window count, even when the operator
had saved a limit in Processing. The training view separately loaded the saved
settings and could reject the same input later.

The builder now reads the existing `ProcessingSettingsStore` from the same app
root as training, and supplies that snapshot to `EEGTrialDatasetExport.manifest`.
The exporter validates it and passes it directly to the canonical dataset loader.
Invalid settings or an exceeded training-window limit fail preparation; no
prepared manifest is returned. There is no truncation or second extraction path.
The public core API retains its explicit default for callers that deliberately
use default settings. It does not read application preferences implicitly.

The limit applies to training records. It does not cap evaluation/control
exposure, modify labels, select more favorable windows, alter features or prove
sufficient training data. A prepared manifest remains a source/label document,
not a frozen profile or a guarantee of successful training. Training reloads and
validates the settings current at that operation. If settings change between
operations, preparation and training may legitimately have different acceptance
outcomes; the resulting profile stores the settings actually used to fit it.

## Regression coverage

`TrialDatasetExportTests.testRecoveredManifestUsesCanonicalExtractionAndPinsSource`
writes a complete synthetic recording with recovered planned/reviewed trial
evidence. A one-window training limit rejects preparation with `resourceLimit`;
a larger limit succeeds and the same loader extracts the expected bounded set.
Changing that limit for an evaluation-only source leaves manifest bytes unchanged.
The existing controls test continues to reject control recordings for training.

```sh
swift test --package-path apple --filter TrialDatasetExportTests
./apple/build-native.sh all
```

These are synthetic software checks. They do not establish headset performance,
physiological classification or a scientifically sufficient window count.

Local validation on 2026-09-15: both exporter tests passed (including all four
control-condition cases), macOS/iOS simulator/visionOS simulator builds succeeded,
and the independent compiled-source fingerprint check passed. The saved-settings
selection in the builder is covered by source inspection and compilation; no new
interactive builder-limit qualification was performed in this change.
