# Native training cancellation

The independent native training workflow accepts cancellation without changing
its model recipe or raw acquisition. `DatasetTrainingView` retains the detached
training task and offers Cancel training while it is running. The UI remains
busy until the worker resolves, so a replacement training job cannot start from
that view while the old job is still fitting or saving. Manifest import remains
a separate bounded read and does not offer this training cancel control.

`EEGTrainingData.prepare` checks task cancellation on entry, while validating
records, during normalization and feature ranking, and before returning.
`EEGMentalTraining.fit` checks before fitting, during projection and class fitting,
and before returning. PCA checks before and after both Accelerate SVD calls.
`EEGProfileCreation.train` checks around fitting and before returning the validated
artifact; retraining uses this same path. Profile save checks on entry and after
writing/synchronizing its private temporary file, immediately before the exclusive
hard-link publication. The existing defer removes temporary files on failure.

These are cooperative checkpoints, not a deadline or preemptive interruption.
An individual reduction, JSON operation, SVD or filesystem call can finish before
cancellation is observed. The link operation is the publication commit point.
Cancellation racing after the last check may lose to publication: in that case
the saved profile is retained and reported as saved. No post-publication
cancellation check falsely reports that a saved file was never published. Other
I/O failures retain their existing error semantics.

No thresholds, features, profile schema, classifier values or physiological
qualification gates changed. This is our implementation, not a claim about
Cortex's cancellation behavior.

## Evidence

`ProfileCreationTests.testCancelledTrainingAndSaveDoNotPublishAndRetryMatches`
uses the existing synthetic training fixture. Before the fix, a self-cancelled
task trained and saved a file; the regression test failed. After the fix both
operations report CancellationError, the target directory is empty, and an
uncancelled retry produces identical profile bytes and saves successfully.
Existing fitting, preparation, roundtrip, lineage and private-save tests also
pass (11 selected tests total).

```sh
swift test --package-path apple --filter 'ProfileCreationTests|MentalTrainingTests|TrainingDataTests'
./apple/build-native.sh all
```

The regression deliberately establishes cancellation before entry, avoiding a
flaky timing-based test. It does not establish a maximum cancellation latency or
inject cancellation during a filesystem/SVD call. The UI control requires
interactive cancellation qualification; build success alone does not establish
that interaction. No real recording or wearer experiment is used here.

Final local macOS, iOS simulator and visionOS simulator builds succeeded on
2026-09-15 after the UI control was added. The source-identity oracle also passed
against the updated core. Physical-device operation and interactive cancellation
latency remain unqualified.
