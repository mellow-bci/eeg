# Evaluation receipt cancellation

Independent reliability fix, 2026-09-15. Acquisition, decoding, inference values,
profile settings and receipt schema/algorithm versions are unchanged.

## Source finding

At `6d547d3`, recording traversal, sequential inference and optional comparison
already checked Swift task cancellation. `DatasetEvaluationView` additionally
checked the detached worker after evaluation and guarded publication. However,
`EEGEvaluationArtifact.make` had no cancellation boundary: calling it from an
already-cancelled task still returned a complete receipt. This was a shared-core
contract gap, not evidence that the app displayed a cancelled result.

The deterministic regression
`LabeledEvaluationTests.testCancelledReceiptCannotPublishAndIndependentRetryMatches`
first failed on that implementation with “Cancelled worker published an evaluation
receipt.” It builds a real fixture report, cancels only its detached worker using
`withUnsafeCurrentTask`, then invokes the same internal receipt constructor used
by the public evaluator. No timing sleeps, vendor runtime or headset are involved.

## Behavior

The public evaluation entry and internal receipt constructor now check
cancellation on entry. Receipt construction also checks each prediction and trial
row, and immediately before and after Foundation JSON serialization. Cancellation
throws `CancellationError`; it is not converted to a successful receipt with an
unavailable comparison. An independent retry does not inherit cancelled task state.
No output file is created by this API; callers own publication/export.

These are cooperative checks, not preemptive termination. Foundation serialization
and aggregate calculations remain synchronous. Cancellation during those operations
is observed at the next check; there is no claimed maximum interruption latency.
A cancellation that arrives after the final check still requires the caller's
publication guard. The existing app guards remain in place. Disk export cancellation
and forced process termination are separate concerns.

## Verification

After the change, all 12 `LabeledEvaluationTests` passed. The regression verifies
that the cancelled constructor throws and a fresh retry produces byte-identical
output to the uncancelled baseline, with system control disabled. Other tests in
that selection cover numerical/receipt accounting, source provenance and rejection.

```sh
swift test --package-path apple --filter LabeledEvaluationTests
```

The macOS, iOS and visionOS native builds succeeded. The complete 24-trial
synthetic CLI check also passed, matching the pre-change canonical receipt byte
for byte (SHA256 `68a8f7d6d42d46625c25d13685b15e954575114fefe23eb9ea0f0022eec2a18f`).
This pass did not repeat the native UI interaction.

This is software evidence only. It does not qualify physiological intent,
headset interruption, physical storage failure or complete production readiness.
