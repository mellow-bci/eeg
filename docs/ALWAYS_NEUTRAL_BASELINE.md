# Always-neutral evaluation comparator

`native-labeled-evaluation-9` adds `always_neutral_baseline` to the native receipt.
This is a signal-free reference rule, not another trained model or processing path:
for every evaluated window it predicts `neutral`, regardless of EEG validity,
artifact rejection or shadow arming. It uses the same class labels and evaluated
window set as the learned detector; the original predictions remain unchanged.

The existing metric summarizer computes pooled and per-session TP/FP/FN,
precision/recall and rejection counts. Baseline rejection is zero because it needs
no signal. A missing actual class has unavailable recall; a class never predicted
has unavailable precision. In an imbalanced set with three neutral windows and
one task window, this rule gets three correct while detecting no tasks. That is
why overall accuracy alone is inadequate.

Cued-trial baseline summaries retain declared, scored and unavailable trial counts
from the same label/cue evidence policy. Candidate observations are always zero:
zero task detections and zero neutral false-positive task candidates. When no trial
has usable cue evidence, the observation fraction stays null, not an invented zero
rate. These summaries do not inherit the classifier's signal-availability rate as
a baseline performance claim; the comparator does not use signal features.

The UI shows per-class window recall beside the baseline and describes the trial
behavior; the receipt contains pooled and per-session window and trial summaries.
Missing cue data is not repaired. Neither a favorable comparison nor zero neutral
false positives establishes useful task discrimination, significance, neural
origin, safe control or prospective qualification. Grouped permutation testing
and physiological experiments remain outstanding. Correlated windows must not be
counted as independent trials.

This implements the protocol's trivial comparator while preserving the canonical
native evaluator for UI and CLI. No recording, model parameters, vendor assets or
raw acquisition code are changed.

Reproduce with:

```sh
swift test --package-path apple --filter LabeledEvaluationTests
```

Checkpoint 2026-09-15: nine native evaluation tests passed, covering imbalance,
rejection retention, absent classes, per-session receipt fields and known versus
missing cue evidence. A duplicate receipt-definition key was caught during
implementation and removed before these final checks. The native CLI produced
20 neutral true positives, 20 neutral false positives and zero task recall for
the balanced 40-window synthetic fixture, while preserving the detector's own
40 predictions. All three native builds passed. The added UI disclosure compiled
but has not received interactive layout/accessibility qualification. No headset
capture or physiological experiment was performed.
