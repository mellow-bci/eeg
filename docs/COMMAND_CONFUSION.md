# Command confusion accounting

The independent native evaluator exposes pooled `confusion` and
`session_confusion` in `eeg.native-evaluation.v1` receipts, starting with
`native-labeled-evaluation-10`. Training, inference, thresholds and acquisition
are unchanged. This is descriptive error accounting, not a recovered Cortex
algorithm or physiological qualification.

Actual labels index rows. Each row contains:

- `predicted_counts`: a dictionary of predicted labels to integer window counts;
- `rejected_windows`: the number of null predictions, including unusable,
  unarmed, outlier and persistence-rejected windows;
- `actual_windows`: all predicted counts plus rejections.

Rejection is outside the label dictionary, so even a command named `rejected`
cannot collide with the missing-prediction count. Explicit neutral remains an
ordinary prediction. Absent classes retain zero rows and columns. Counts are not
normalized: zero exposure is visible instead of becoming a misleading rate.
The internal summarizer retains any observed label even when omitted from its
class argument; production evaluation already validates labels against the
profile. Predictions remain the authoritative detailed records.

The Calibration UI presents these counts in a disclosure for the pooled result
and within each session. The presentation uses textual labels and counts rather
than color alone. Interactive and full accessibility qualification of this new
disclosure remains outstanding; native target builds are compilation evidence.

## Verification

`LabeledEvaluationTests` covers wrong-command, neutral and rejected outputs,
an absent class, a class literally named `rejected`, shuffled input order,
conservation of window totals, consistency with existing class metrics and
aggregation across two sessions. Receipt tests cover serialization and per-session
window totals. Ten selected tests passed on 2026-09-15. macOS, iOS and visionOS
native builds passed.

The existing four-session synthetic dataset was evaluated through `EEGEvaluate`.
An independent Python `Counter` reconstruction from each receipt prediction
matched every pooled and per-session cell, all row totals and all rejection
counts: 40 windows, evaluation sessions c and d. Local inspection receipt:
`/tmp/eeg-confusion-cli.json` (temporary, not a durable fixture dependency).

Reproduce the deterministic tests with:

```sh
swift test --package-path apple --filter LabeledEvaluationTests
./apple/build-native.sh all
```

These checks do not supply independent human labels, measure generalization or
make correlated windows independent trials. No hardware session was performed.
