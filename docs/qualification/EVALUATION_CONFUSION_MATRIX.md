# Evaluation confusion matrix — 2026-09-15

The native evaluation report presents canonical confusion counts in a shared
SwiftUI grid for both pooled and per-session results. Declared labels are rows;
experimental predicted labels are columns. Rejection and total windows have
separate columns. Class names are the union of actual and predicted labels, so an
unexpected predicted label cannot disappear from the display. Zero counts remain
visible; no normalization or confidence estimates are introduced.

Cells expose their declared/predicted label and count to accessibility. Accent
backgrounds mark label matches; rejection has its own label and count, so color
is not required to distinguish it. Horizontal scrolling accommodates multiple
classes. The descriptive text distinguishes correlated windows from independent
trials and does not claim physiological validity or enable control.

## Verification

- `./apple/build-native.sh all`: macOS, iOS simulator and visionOS simulator pass.
- `swift test --package-path apple --filter LabeledEvaluationTests`: 12 tests pass.
- The existing multiclass test checks conserved windows, a real class named
  `rejected`, separate no-prediction accounting, ordering invariance and session
  totals. The display consumes these canonical rows without another classifier.
- This change has not yet been visually qualified with an evaluation report
  loaded in the running app. Build and accounting checks are not visual,
  VoiceOver or physiological qualification.
