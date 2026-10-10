# Training lifecycle static evidence, 2026-10-11

Pinned CortexService arm64 body hash in manifest. These captures are instruction
observations, not executed Cortex output or physiological validation.

## Control and collection

`runTraining`100b31a68 reads control, startAfterTimeInSec and trainingTimeInSec.
At100b31c50 the dispatch base100b31c60 adds four times the byte indexed from
102647f98. Actual bytes18,1c,0e,00,3c,00 prove controls0idle,1collection,
2accept,3completion(event6),4reset,5completion(event7). Negative and>5 controls
trap in vendor; our typed error replaces trap.

Collection calls onTrainingStarted every time. That locks trainingAction,
autoSamplingNeutral, activeActions, activationThreshold, action1..4Threshold,
rebuildSignature. It does not lock trainingControl. Primary nonempty advances
sample counter by MatrixStream.stepSizeInSample even when validity is false.
Started event1/increaseTotalOfTimesTraining happen once per reset state.
QElapsedTimer elapsed milliseconds are integer-divided1000 before floating
conversion. Start timer gives elapsed0. Float32 profile duration+1.5 is wall cap.

At31f74..31f98 decoded FCMP/FCCMP conditions append only when
`sampleSeconds > startAfter && sampleSeconds <= duration && elapsedWholeSeconds < wallCap`.
If not in append region but sampleSeconds<=duration and wallclock<cap, wait.
Otherwise finish collection. Validity+primary nonempty gate append; secondary
empty is still paired. At configured maximum, remove oldest paired epochs.

Finish collection emits event2 if primary epoch count>=minimum or3 otherwise,
once per reset; enough calls onTrainingWaitingForAcceptReject (unlocks only
trainingControl), insufficient calls onTrainingCompleted (unlocks all above plus
trainingControl). `completed` boolean means insufficient on this path; active
flag and timer are not reset here. Previously trained nonneutral action updates
threshold: K0=>0, K>0=>b+.5*(1-b), b=1/(K+1), and score positive-history/count,
emptyhistory=>0. Both depend on explicit supplied profile/history inputs.

## Accept/reject/reset boundaries

Accept below minimum calls completed, emits7, completedtrue, but does not clear
active/timer. Enough calls onTrainingAccepted, emits4, clearsactive and timer.
Accepted body builds classifier with booltrue; success attempts save, failedsave
logs without clearing. Buildfalse clearsclassifier and attempts empty save.
Then clears error bank, counts training, updates trained signatures, optionally
updates brain coordinates, and calls completed. Event4 therefore does not prove
successful fitting or persistence. Reference lifecycle reports FitResult apart
from event. Real builder/persistence are required injected callbacks, never
default simulated success. Brain-map/count/cache algorithms are not recovered
by that callback interface; no parity claim for them.

Controls3/5 call completed, emit6/7, clearactive and invalidate timer. Control4
removes training action data/cache, rebuilds with boolfalse, updates trained
signatures, resets action training count/brain coordinates, optionally updates
threshold/score for nonneutral, emits5, clearsactive. Reference reset callback
owns these bank/cache side effects; it must report actual outcome.

Separate resetTrainingState captured previously at100b32e88 clears pairedbuffers,
f0..f3 flags, counter and timer, sets auto0/action1/control0. The model resets
internal state; caller applies profile fields. Accept/reject itself retains epochs.

## Independent safety choices and limits

Require finite rectangular matrices, finite score history, monotonic nonnegative
clock, positive sample rate/step, explicit valid duration/minimum/maximum and
checked sample counter overflow. These are bounded independent policies, not
recovered vendor guards. Callback bank fitting test uses analytic caller-supplied
feature columns and verifies actual means/covariance/counts; reports saveFailed
because no classifier persistence occurred. Tests do not prove original rawEEG
feature recipe, upstream validity, trained profile parity or command efficacy.

Matrix::combine10213923c method1 at+80..376 verifies equal source row counts,
sums widths and copies each source row into destination at accumulating column
offset. BuildClassifier at2fb88 and2fc08 calls method1 separately on primary and
secondary lists. ReferenceTrainingEpochAssembly follows column order and rejects
shape mismatch; explicit maximumCells and finite checks are independent policies.

Reset error-bank clear differs from acceptance:3209c..320a0 is only on failed
rebuild, while accepted33630 clears after either outcome. Transition separates
clearErrors from updateActions and preserves that branch difference.
