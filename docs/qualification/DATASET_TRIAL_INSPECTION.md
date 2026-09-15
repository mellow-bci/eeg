# Dataset trial inspection — 2026-09-15

Dataset preparation now opens the existing `TrialEvidenceReviewView` in a native
sheet for each finalized recording. The sheet expands that shared component and
keeps dataset preparation mounted. No second evidence loader, acceptance path,
label editor or acquisition path was added.

The shared review view explains missing trial plans in plain language and retains
the underlying error in a Technical details disclosure. Inspection does not make
a recording eligible for training. The existing dataset validator still decides
whether its recorded plan, reviews and windows satisfy the contract.

## Checks

- Final macOS, iOS simulator and visionOS simulator builds passed.
- macOS: opened the first saved recording from dataset preparation, read its
  journal, and observed the expected missing-plan failure.
- Final build: verified the actionable missing-plan message and collapsed
  technical-details disclosure in the accessibility tree.
- Initial sheet layout visually checked in dark mode; Done returned to dataset
  preparation. Both existing recordings remained byte-identical to their known
  hashes. No labels, dataset, profile or recording were saved.
- No headset scan, audio cue or physical experiment was started.

A successful planned-session review through this sheet and cross-platform runtime
accessibility remain unqualified; builds alone do not establish those outcomes.
