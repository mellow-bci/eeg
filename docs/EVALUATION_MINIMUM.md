# Configurable evaluation window minimum

The local Calibration workspace and `EEGEvaluate` share a caller-selected
`minimumWindowsPerClass`, default 10. It must be a positive integer. There is
no tier or silent clamp. This setting controls admission of a full labeled
evaluation, not model training, inference, rejection, persistence or acquisition.

Each profile class must have at least this many declared evaluation windows,
including unusable and rejected windows. Those windows remain in the result
denominators. This does not establish that enough independent trials or human
sessions were collected. Lowering the setting cannot create physiological
validation or enable system control.

Controls-only evaluation does not apply the per-class requirement, since its
dataset intentionally excludes task examples. The positive setting is still
validated and recorded for reproducibility. The UI allows editing it while idle;
changes clear previous results and export state. It is frozen during evaluation.
The control is an evaluation option, not a change to the saved model recipe.

Starting with `native-labeled-evaluation-11`, every receipt contains the chosen
`minimum_windows_per_class` and its definition. The existing receipt schema is
retained with this additive field. Earlier receipts retain their earlier algorithm
version and implicit default of ten; they are not rewritten.

```sh
apple/.build/debug/EEGEvaluate --manifest DATASET.json --profile PROFILE.json \
  --recordings RECORDINGS --minimum-windows-per-class 20
```

Noninteger, zero, negative and unrepresentable CLI values fail with exit 2 before
evaluation. Insufficient class data fails with exit 1 and no provisional receipt.
The core also validates callers that bypass the CLI or UI.

## Evidence

Fourteen selected labeled-evaluation/trial tests passed on 2026-09-15. Tests
cover unchanged predictions when lowering the default, failure above available
class counts, invalid values, receipt provenance and controls-only behavior.
macOS, iOS and visionOS builds passed. The native CLI integration check exercises
default/custom values, four malformed values, insufficient data and no receipt
on failure. Synthetic recordings only; no hardware or cues were used.

Reproduce with:

```sh
swift test --package-path apple --filter 'LabeledEvaluationTests|TrialMetricTests'
python3 tools/check_native_evaluation_cli.py
./apple/build-native.sh all
```

The new UI field is compiled but has not yet been interactively qualified. This
engineering setting is not a statistical sample-size calculation, evidence of
Cortex equivalence or a physiological accuracy claim.
