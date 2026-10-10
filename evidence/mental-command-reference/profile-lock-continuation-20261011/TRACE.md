# Advisory profile-key locks: exact supported state semantics

Static arm64 LLDB CortexService SHA256 cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a. No vendor values, assets or runtime acquisition changes.

## Body-derived membership rather than exclusion

EmoProfile::lock 0x101235cf0 advances this pointer by8 and calls helper0x100152768 at 0x101235d04. That helper copies the QStringkey and invokes0x100152808; insert helper0x100152980 uses lookup0x100152a28 and retains an existing entry or inserts an absent key. No per-key recursive count is incremented. The uninitialized dummy byte passed to lock's insert helper is not an inferred lock value or ownership token: membership is what set/unlock observe. Captures retain insertion/find/COW branches; a complete Qt hash implementation is not reproduced.

EmoProfile::unlock 0x101235d14 returns without modification on null/emptymap or missingkey (0x101235d2c/34/44), otherwise obtains the entryindex, copy-on-write detaches if needed (0x101235d84), and calls erasehelper0x10045faf0 at 0x101235dac. It removes the one membership; no nested depth or owner authorization appears.

EmoProfile::set 0x1012357f0 finds key in lock map using0x100152658, then calls get/QVariant::equals at 0x101235858/864. Equal values bypass the diagnostic; unequal locked values log 'EmoProfile, setting value for a locked key' at 0x1012358a8. Both routes eventually call value-map writer0x1001776a0 at 0x101235988. **The advisory lock does not block writes.** It is not a mutex, exclusion lock, immutable field guarantee or authorization boundary. Missing values use invalid QVariant from get; custom Qt type equality remains a caller-supplied comparison result in the independent helper, not invented Swift equality.

## Observed mental-command callers and ordered key lists

| Caller | Body/call sites | Per-key operation |
| --- | --- | --- |
| onTrainingStarted | 0x100b330e8, lockcalls3312c..3340c | lock trainingAction, autoSamplingNeutral, activeActions, activationThreshold, action1Threshold, action2Threshold, action3Threshold, action4Threshold, rebuildSignature |
| onTrainingWaitingForAcceptReject | 0x100b334cc,33510 | unlock trainingControl only |
| onTrainingCompleted | 0x100b34cb4, unlockcalls34cf8..35034 | unlock trainingControl then all9 training-startkeys |
| onAutoSamplingNeutralStarted | 0x100b35100,35144..353c8 | lock trainingAction, activeActions, activationThreshold, action1Threshold, action2Threshold, action3Threshold, action4Threshold, rebuildSignature |
| onAutoSamplingNeutralCompleted | 0x100b3547c,354c0..35744 | unlock the same8 neutralkeys |

Every key above is prefixed `cognitiv-`. The caller bodies may perform additional lifecycle state/events beyond those key operations; ReferenceProfileLocks.apply models only the shown membership sequence. It does not schedule, start, stop or accept training, assert lifecycle readiness, or reproduce signal delivery. If training and neutral operations overlap, shared-key membership is idempotent, so neutral completion removes sharedkeys even if training previously locked them. The helper exposes this observed non-refcounted behavior without claiming that production orchestration permits such overlap. trainingControl's acquisition elsewhere is not inferred from its unlock call.

## Independent bounded helper

Internal ReferenceProfileLocks(maximumKeys:maximumKeyBytes:) owns Set<String> lockedKeys and lock/unlock/disposition/apply. It supports ASCIIkeys only, keeping the key domain explicit rather than claiming Swift normalized Unicode equality equals QString code-unit equality. Empty ASCII key is not prohibited by the reference path. A repeated lock is idempotent; unlocking unknownkey no-ops. disposition(for:equalsPreviousQVariant:) always permitswrite and requests diagnostic iff locked and unequal. It consumes only the caller's equality result, not recovered Qt converter/comparator behavior.

Maximumkeys/keybytes are explicit caller-selected support policy, not recovered vendor limits. Multi-key apply stages a candidate and commits only if every boundedoperation succeeds: atomic capacity rejection is our own policy. It is not an inferred vendor rollback or concurrency guarantee. No locks are written to disk by this helper and no Qt hash ordering/bucket allocation is claimed.

Five authored tests cover advisorychanged/unchangedwrites, repeatedlock/singleunlock, missingunlock, trainingstart/wait/completekeysets, neutral/training overlap exposing non-refcounted membership, atomiccapacityfailure and unsupportedunicode/length/configuration. Root coordinates package execution; this agent performed no build or commit. End-to-end reference runtime comparison remains separate.

Reproduction: capture LLDB address bodies as retained. training-lock-calls.txt is a bounded extract of previously captured training-lifecycle-continuation-20261011/lifecycle-bodies.txt; exact call sites and symbols cross-reference that fullcapture. Other address-range captures include adjacent methods, which are not evidence for additional claims. No vendor asset dependency is required for the supported membership helper.
