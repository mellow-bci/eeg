# Calibration navigation qualification

The native calibration page now exposes four named stages: capture trials, prepare
dataset, train profile and evaluate. Adaptive overview buttons jump to stable
section anchors; each section has a return-to-workflow button. These are navigation
controls, not progress or validation indicators.

All existing views remain mounted in the same scroll container. Navigation does
not create a second training pipeline or change acquisition, profile, dataset or
evaluation contracts. Trial review still occurs in Recordings and is explicitly
described before dataset preparation.

## Observed checks — 2026-09-15

- `./apple/build-native.sh all`: macOS, iOS simulator and visionOS simulator builds passed.
- Running macOS app, disconnected with no acquisition: four named stage buttons
  and section headings exposed in the accessibility tree.
- Evaluate jump brought the evaluation section into view; its return button
  restored the workflow overview. Both layouts visually inspected in dark mode.
- Entered temporary participant pseudonym `ui-navigation-check`, jumped to
  evaluation and back: the text remained. Cleared it afterward without saving.
- No headset discovery, audio cue, recording, training or evaluation was started.

This verifies this navigation change, not the full physiological workflow,
VoiceOver operation, narrow-window accessibility or full visual redesign.
