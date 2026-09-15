# Native training isolation under held-out interventions

Qualification date: 2026-09-15. Synthetic software evidence only; no headset,
participant, Cortex runtime or application-library changes.

`TrainingDatasetTests.testHeldOutSignalAndLabelChangesCannotChangeFittedProfile`
exercises the actual finalized JSONL recording writer, canonical dataset reader,
feature extraction and native profile fitter. Two synthetic training recordings
contribute 40 accepted windows in total, 20 per class across two sessions.
The baseline also includes a separate 20-window evaluation recording.

Three interventions keep the training sources and settings fixed:

1. Swap neutral/task labels on the evaluation recording. Assert that every
   evaluation label flips while extracted evaluation features remain identical.
2. Replace the evaluation recording with a distinct recording whose two signal
   frequencies shift by 4 Hz. Assert that extracted evaluation features change.
3. Remove evaluation sessions entirely. Assert that no evaluation windows remain.

For each intervention, refit from the canonical reader's training records and
require the entire serialized profile to match the baseline bytes. This covers
normalization, feature selection, PCA, Gaussian parameters, settings, training
provenance and digest, rather than checking only training session names. All
fixtures retain their original sample bytes; intervention recordings are separate
temporary files and are removed after the test.

## Observed result

The new test passed in 21.192 seconds. All five `TrainingDatasetTests` passed with
zero failures in 46.552 seconds using the local Debug build. Reproduce with:

```sh
swift test --package-path apple --filter TrainingDatasetTests
```

This establishes invariance for these concrete signal/label interventions under
the tested implementation. It is not exhaustive proof against all leakage,
independent acquisition, externally selected hyperparameters, or a model tuned
after viewing evaluation results. Existing exact recording/excerpt reuse checks
remain separate gates. No physiological classification, cross-session robustness,
mental-command accuracy or system-control qualification follows from this test.
