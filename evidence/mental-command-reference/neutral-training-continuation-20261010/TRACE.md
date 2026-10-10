# Neutral training lifecycle

Reference binary identity and static capture hash are in manifest.json. Full
runAutoSamplingNeutral and callbacks are in the earlier
training-followup-20261010/selection-neutral.txt; this continuation captures
init, resetTrainingState, runTraining and bounded Matrix list helper bodies.
No binary, private profile or learned vendor asset is included.

## Body-derived behavior

- `init` 0x100b37bf0 reads `cognitiv-minEpochsToTrain` at 0x100b384a4,
  converts it with QVariant::toInt and stores it at this+0xb0 (0x100b384e0).
  This is a configurable count of buffered Matrix epochs, not sample rows.
- `runAutoSamplingNeutral` 0x100b31608 reads profile trainingControl and
  autoSamplingNeutral. At 0x100b3173c–0x100b31754, auto=1 plus control=1
  becomes effective auto=0; otherwise auto is unchanged. Only 0 and 1 are
  implemented; other values reach the exceptional branch.
- Collecting calls onAutoSamplingNeutralStarted on every call, sets this+0xf3,
  then appends only if the explicit validity argument is true and the first
  Matrix is nonempty. The second Matrix is appended without a separate
  isEmpty test. Helper 0x100b39df8 is Qt list insertion of a Matrix object.
  The two buffers are this+0x80 and this+0x98, with sizes +0x90 and +0xa8.
- Effective auto=0 is inert if not collecting. Otherwise it clears +0xf3 and
  compares primary buffer size against +0xb0. At or above minimum, it sets
  trainingAction=1 (neutral), builds with the existing classifier, saves on
  build success, and on build failure clears the classifier then attempts
  to save the empty classifier. Save failure after successful build logs an
  error without clearing the built classifier. A build attempt clears the
  classifier error set and updates trained actions even on fitting failure.
- Every active collection stop calls onAutoSamplingNeutralCompleted, clears
  both buffers, emits event integer 8 and sets autoSamplingNeutral=0, including
  insufficient-data stops. Event 8 must not be described as training success.
- Started 0x100b35100 and completed 0x100b3547c lock/unlock trainingAction,
  activeActions, activationThreshold, action1–4Threshold and rebuildSignature.
- resetTrainingState 0x100b32e88 clears buffers, timer/counters and the word
  containing the collection flag, then sets auto=0, trainingAction=1, control=0.

## Independent support policies and unresolved gates

ReferenceNeutralTraining is comparison-only and takes minimumEpochs explicitly.
Its configurable maximumBufferedEpochs, positive minimum requirement,
finite/rectangular input validation and atomic validation failures are our
support policies, not recovered vendor algorithms. Invalid input retains state
and exposes an error; callers must stop/reset or remediate, never claim completion.

The injected synchronous fitting callback must actually build/save and return
its outcome; there is no default successful fitting path. This primitive does
not itself fit or persist a classifier. The upstream meaning of the validity
boolean, complete epoch-window recipe, training acceptance, full rebuild policy
and real profile/reference outputs remain unverified. Empty matrices are
represented with native arrays, not Armadillo storage objects.

Tests cover paired buffering, repeated lock requests, validity/empty gates,
minimum boundary, effective control stop, insufficient-data completion,
build/save failure distinction, atomic resource errors and reset. These are
body-derived branch expectations, not recorded Cortex output comparisons.
