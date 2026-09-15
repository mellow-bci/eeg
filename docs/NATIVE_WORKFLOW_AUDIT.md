# Native mental-command workflow audit — 2026-09-15

Code checkpoint: `b0f6d90`. This audit preserves the complete feature-parity goal;
it does not redefine completion as the pieces implemented below.

| Requirement | Current code/evidence | Unfinished proof or work |
|---|---|---|
| Independent acquisition | `AcquisitionModel.swift`, `Decoder.swift`; original notifications and decoded samples retained | Fresh physical native EPOC X start/reconnect/sleep-wake qualification; supported mode only |
| Planned task evidence | `TrialCueController`, `TrialSession`, `TrialPlan`, `TrialEvidence` and their core tests | Speech/UI handling has compiled but not been interactively or acoustically qualified |
| Recorded labels | Recording-store revision recovery validates plan, order, rest and timing | Declarations are not physiological ground truth; observations default unknown |
| Dataset preparation | `TrialDatasetExport` and `DatasetBuilderView`; synthetic recording-to-window test | Real independently acquired sessions; interactive selection/export check |
| Personalized training | `MentalTraining`, `ProfileCreation`, `ProfileStore`; reference-vector and cross-language tests | Participant-specific prospective calibration/acceptance and artifact robustness |
| Held-out evaluation | `LabeledEvaluation`, `EvaluationArtifact`, prepared-manifest UI | Real whole-session precision/recall, false activations, latency and cross-session evidence |
| Live inference | `ReplayInferenceView` invokes offline `EEGReplayInference.run`; acquisition contains no profile-inference consumer | Implement live shadow processing through canonical windows and detector; persist provenance/results without actions |
| Controlled output | `EEGExperimentalProposal` always has nil command and disabled control | Keep disabled until qualification and a confirmation/cancel policy; no actionable output claim |
| Recording resilience | Abort handling and injected completion-write/flush tests | Dedicated bounded I/O execution, prolonged operation, physical fault/power-loss evidence; failed rollback can remain uncertain |
| Other Cortex capabilities | Individually scoped rows in `capability-matrix.json` | Contact classifications, gestures, performance targets, EDF and other hardware remain separately gated |

## Next implementation order

1. Extract one reusable analysis-window → feature → detector step from replay;
   test identical proposals for identical validated inputs, including invalid-window
   resets. Do not fork another feature recipe for live capture.
2. Add a bounded serial native shadow-processing consumer with explicit overload,
   disconnect and profile-change resets. Capture raw measurements independently of
   whether inference succeeds. Persist profile/configuration identity and rejection
   reasons; do not enable system actions.
3. Move blocking recording I/O out of UI/Bluetooth delivery while preserving order,
   abort semantics and evidence acknowledgements. Measure latency and queue bounds.
4. Qualify UI/audio and the exact headset configuration with fresh participant
   readiness. The most recent attempted UI observation found the Mac locked;
   historical readiness does not authorize a new physiological experiment.
5. Run the documented independent-session protocol and artifact/ordinary-activity
   challenges. Accept or reject the trained profile from measured evidence.
6. Expand the remaining capability-matrix rows one at a time, preserving these gates.

CI passed at `0a6750e` (run 34911644557). The `b0f6d90` run 34911834013 was still
in progress when inspected. Local `b0f6d90` validation recorded 93 passing tests
and three successful native builds; none establishes live physiological accuracy.

## Shared window processing implemented

`EEGWindowInference` now owns the sequential analysis-window → spectral features
→ detector step, and `EEGReplayInference` delegates to it. Rejected windows reset
detector state; malformed window structure rejects explicitly. Results retain
ordinal, reasons and experimental candidate and explicitly disable control.
Replay still validates the complete source and excludes exact training content
before releasing its report. The shared step itself does not assert held-out
status: that remains a host-level whole-recording check.

A native regression compares shared sequential processing with the replay report
on the same finalized synthetic recording, checks identity rejection and malformed
window handling. Existing numerical/detector tests remain in the suite. A bounded
live consumer and acquisition/UI integration are still required; extracting this
component does not mean live inference is running.

## Bounded live shadow consumer implemented

`EEGLiveInference` serializes metadata/sample input through the existing canonical
window assembler, sample validator and shared window processor. The default limit
is 512 pending inputs (including work in progress), configurable at construction.
Event payloads over the existing 4 MiB event limit reject during processing.
This is a count bound, not a total-byte memory budget. A false `submit` return
means no admission; overload increments the generation and queued older work is
discarded. Stop rejects future submissions. Reset, overload and malformed input
clear window/detector continuity, requiring fresh configuration/stability input.

Callbacks run on the worker queue. Hosts must check generation again on UI delivery
and keep raw recording independent of inference admission. No callback authorizes
an action. The callback can race a later reset, which is why generation accompanies
every result. The consumer does not drain a partial window into a fabricated result.

Tests compare its complete-window results with canonical replay on identical
synthetic samples, use a suspended worker to prove bounded admission and stale
queue rejection, and verify stop rejects further input. These are software tests,
not live headset evidence. Acquisition/profile UI integration and total-byte queue
budgeting remain unfinished; this component alone is not a running live workflow.

## Acquisition shadow integration

Acquisition now submits decoded samples to `EEGLiveInference` after recording
those measurements. `LiveShadowView` starts it explicitly for the inspected
profile, a declared participant and a non-training session ID. Active recording
and stable transport are required. Start metadata includes profile/feature IDs;
window candidates/reasons and stop causes are separate recording events with
system control explicitly disabled. Results are accepted on the main queue only
if both the consumer token and generation still match.

Loss of transport, overload, input rejection, recording failure, recording stop
or profile-view closure stops inference and clears the displayed candidate. No
restart occurs automatically. Samples continue recording if only inference stops.
The producer currently runs on the main queue and raw file I/O remains synchronous;
this is not a latency-qualified architecture yet. Window ordinals are relative to
the shadow run, not a global recording-window index. More precise per-window
source-range provenance remains to be added before offline/live alignment can be
qualified. Whole-content training reuse can only be checked after capture ends.

The core live/replay regression remains the current software evidence. This app
integration has not been exercised with a physical headset or interactive profile
controls, and no physiological accuracy or production readiness is claimed.

## Shadow source ranges

Shared window results now retain first/last source sample indices, sample count
and first/last receipt timestamps. Empty rejected windows have unavailable bounds.
The acquisition log records these as `first_sample_index`, `last_sample_index`,
`sample_count`, `input_start`, `input_end`, with `recorded_receipt_seconds` timing.
The separate `receivedAt` remains callback-delivery time. Start/result/stop records
share `shadow_run_id`; results also include reset generation. Thus a restarted
run's ordinal zero cannot be confused with the previous run's ordinal zero.

Regression assertions check the exact indices and timestamps of known synthetic
windows. Existing live/replay equality checks now include these fields. This
provides alignment metadata, not proof that live capture matches replay under
real transport/load. A full alignment audit and latency measurement remain due.

## Live queue payload budget

The shadow consumer now admits at most `maximumPendingInputs` inputs (default
512) and `maximumPendingEventBytes` event bytes (default 4 MiB), including the
currently processing input until delivery returns. Each event also retains the
4 MiB individual limit. Admission rejects oversized events before enqueueing;
subtraction-based capacity checks avoid integer overflow. Samples must have the
canonical 15 ADC words and exactly 14 channel values per present dictionary,
with the shared sample validator accepting their contents before enqueueing.
These bounds cover logical input payloads, not exact process RSS, allocator
capacity or caller-owned storage. The analysis window and model remain separate.

Budget rejection returns false and invalidates the generation, just like count
overload. The native host stops shadow inference visibly while raw recording
continues. Stale queued work releases its accounting when drained. Reset/stop do
not pretend queued memory has already been released. Limits are constructor
configuration; they are not yet exposed in application settings.

A suspended-worker test fills the byte budget below the count budget, verifies
rejection/generation invalidation, drains stale work, and verifies accounting
recovery and oversize rejection. This is deterministic offline evidence, not a
hardware throughput or memory benchmark.

## Application processing-limit settings

The profile's live inference panel now exposes persistent pending-input and
event-byte limits under Processing limits. Positive integer validation blocks
invalid values; fields lock during a run. Restore defaults returns 512 inputs
and 4,194,304 event bytes. Each `shadow_start` stores the selected limits, so
later analysis need not infer them from current preferences. Large values can
increase retained data and latency; no claim of an optimal hardware setting is
made. The per-event parser limit remains 4 MiB.

Startup admission rejection (for example, a byte budget too small for device
metadata) stops the candidate consumer and rejects inference startup without
aborting the raw recording. Actual recording-write failure retains the existing
storage-failure path. This corrects the former shared catch that incorrectly
classified initial queue rejection as a recording storage failure.

Native platform compilation verifies the view and call sites. Interactive
settings persistence, startup behavior under a physical stream and accessibility
remain unqualified until exercised in the application.

## Native profile opening exercised — 2026-09-15

The Mac became available. On the current SwiftUI profile importer, the selected
repository `apple/Fixtures/spectrum/mental-profile.json` left Open disabled;
Spotlight reported `public.json`. Broadening the picker to `.data` did not resolve
it and was removed. The macOS profile picker now uses `NSOpenPanel` with the same
JSON filter, one-file selection and the existing bounded `readDocument` validator.
iOS/visionOS retain the SwiftUI picker. Both feed one profile-loading function;
no validation or training path was duplicated. Opening is disabled while a panel
or load is active.

The native panel enabled Open. The application subsequently displayed the fixture
profile ID `635267ad37d2d8fa13c18b30053edce07c4803e94abbf35ca4a6694f5a65aa61`,
participant `participant`, two training sessions and `neutral, task` classes,
with command output disabled. Computer-use inspection timed out after panel close;
a two-second process sample showed an idle main event loop. Bringing the app to
the foreground through Finder restored inspection. This does not establish the
root cause of that observation timeout.

Processing limits expanded to 512 and 4194304. Entering zero produced the positive
integer validation message. Defaults were restored and the fixture profile was
closed. It was opened from the repository, not copied into the saved-profile
library. No hardware connection, cue, physiological experiment or command was
started. Persistence across application restart and other document pickers remain
to be exercised. Three native platform builds passed for the panel change.

## Bounded recording writer integrated

`EEGQueuedRecordingStore` now owns the native acquisition writer and serializes
all writes through the existing `EEGRecordingStore` format/validation. Normal
BLE notifications, decoded samples, decode errors and transport status enqueue
without waiting for disk I/O. The default admission limits are 1024 inputs and
4 MiB of accounted logical payload, configurable at construction. Samples use
fixed channel cardinality and a 512-byte logical charge; event charges count
UTF-8 key/value bytes. These are admission bounds, not exact heap/RSS bounds.

Admission is not persistence. Trial evidence, annotations, shadow events and
finish use ordered synchronous barriers: earlier admitted measurements precede
them, and trial acknowledgement retains the store's write/synchronize guarantee.
These less frequent barriers can still block the UI, especially on a stalled
disk. A fully asynchronous control/cue acknowledgement design remains unfinished.
Calls must come from one host executor; the native host uses its main executor.

Overload, invalid admission or asynchronous write failure invalidates the writer,
discards pending work and aborts without a summary. The incomplete file preserves
whatever was successfully written; it is not presented as a complete capture.
A generation-tagged failure callback prevents an old failure from aborting a new
recording. The native host stops the recording and trial/shadow workflow on error.
Abort/finish also remain synchronous barriers. Process termination can lose
queued measurements and leaves the recording incomplete; no power-loss guarantee.

Tests exercise ordered samples/events and trial sample-count acknowledgement,
finish draining, count and byte overload, injected disk failure, lack of a false
completion marker, accounting release and a new generation after abort. The full
suite passed 100 tests; the strengthened trial-order check was then rerun in the
focused queue suite. Three platform builds passed. Physical stream throughput,
long-duration memory, stalls, shutdown and cue timing require qualification.

## Recording writer observability

`EEGQueuedRecordingStore.statistics` provides one lock-consistent snapshot per
recording generation: admitted, written, discarded and failed asynchronous
inputs; current/peak queue occupancy and logical bytes; maximum queue wait and
write duration. Start resets measurements. Discarded means admitted work skipped
after invalidation; rejected admission is not counted as admitted. A write that
throws is counted separately, since a partial write may have reached the file.

Durations use `ProcessInfo.systemUptime`: admission to worker start, and worker
start to the underlying append return, respectively. They exclude synchronous
control operations, final filesystem synchronization, radio/decoder delays and
consumer latency. Maximum values are neither percentiles nor an acquisition
latency claim. Payload accounting is not heap/RSS measurement.

Before successful completion, the writer persists `writer_statistics` with
schema `eeg.writer-statistics.v1`, configured limits, counters and timing basis.
The completion marker follows only if that event and completion succeed. An
aborted recording need not contain final statistics; diagnostics retain the
in-memory snapshot until the next start. The Diagnostics view polls snapshots
and shows unavailable timing as “No writes observed”. It never converts absent
measurements to a successful throughput claim.

Tests verify suspended-queue high-water counts, persisted written counts,
invalidated work accounting, injected failed-write counts and generation reset.
The full 100-test suite passed; no hardware-rate benchmark was performed.

The rebuilt macOS Diagnostics page was inspected with acquisition disconnected:
all counters were zero and both duration fields showed “No writes observed”. No
recording was started during this UI check. Snapshot publication skips unchanged
values to avoid unnecessary idle view invalidation. Platform builds passed.

## Recorded live-output verification

`EEGShadowVerification.run` uses the canonical finalized record reader and starts
the same analysis-window assembler and inference processor at the selected
`shadow_start` event. It does not align a mid-recording run to windows beginning
at sample zero. Device metadata comes from preceding recorded metadata; stable
startup follows the native host's guarded start contract. The verifier supports
the current generation-zero run protocol; reset/restart must have a new run ID.

The selected profile, participant assertion, session, feature recipe, output
status/control flag, candidate/rejection reasons, ordinal, sample indices/count,
and receipt-time bounds are checked. Exact training content is rejected after
the same complete read. Duplicate/out-of-order lifecycle evidence rejects.
Source read/schema/completion failure discards the provisional comparison.

The report includes source SHA-256, mismatched and missing ordinals, counts and
stop reason. `completeMatch` requires at least one output, no differences or
missing full-window outputs, and a recognized ordinary stop. Pending worker
windows discarded at stop can therefore produce a missing-output report. Partial
window tails are not invented as live outputs. A match is software consistency
only, not wearer identity, label accuracy, source authenticity or mental-command
qualification. No actions are enabled.

The existing offline panel exposes comparison using a selected recording, current
profile, recorded run ID and window limit. Run-ID discovery in the UI and physical
live/replay qualification remain pending. The UI has compiled on three platforms;
the new comparison controls have not yet been exercised interactively.

Tests generate a synthetic live consumer run starting at sample 13, persist its
outputs, and independently replay the recorded boundary. They verify equality,
altered candidate detection, missing outputs and stop detection. The full suite
passed 102 tests; focused follow-up coverage also checks incomplete source and
invalid limit rejection. These fixtures provide no physiological evidence.

## Run selection from finalized recordings

The offline comparison panel now loads a run catalog from the selected finalized
recording and offers only runs referencing the open profile. Manual run-ID entry
has been removed. A configurable listing limit defaults to 1024 runs; exceeding
it rejects the load instead of returning a partial catalog. Each listed identifier,
session and profile field must be nonempty and at most 4096 UTF-8 bytes, and run
IDs must be unique. Listing validates the whole source but does not validate the
run's inference outputs or prove participant identity.

The catalog retains the source SHA-256. Comparison passes that expected digest
to the verifier, which rejects a changed source after its complete read. Changing
the recording clears both selection and previous results. Loading is explicit
and runs off the UI executor; the form is disabled during a load/comparison.

The catalog test checks run/session/profile metadata, source pinning across a
benign post-discovery file modification, duplicate run rejection, invalid limits,
empty recordings and incomplete-source rejection. The full suite passed 103
tests. Interactive run selection and physical recording comparisons remain
unqualified; software discovery is not a physiological validation result.

## Shared native JSON opening

All five JSON import consumers (capture, processing settings, profile inspection,
training manifest and evaluation manifest) now use one platform adapter. macOS
uses NSOpenPanel; iOS and visionOS retain SwiftUI's document importer. Each consumer
keeps its existing bounded read and schema/provenance validation. Cancellation
and leaving the view close the macOS panel without accepting a document.

The macOS interactive check selected the synthetic mental-profile.json fixture
through the training manifest picker. Open was enabled and the filename appeared
in Calibration. Attempting training rejected the wrong schema (missing sessions);
no profile was listed as saved. Reopening and cancelling returned to Calibration.
This tests file selection and rejection, not successful physiological training.
All three native targets built successfully with ./apple/build-native.sh all.
Other consumers share the adapter but were not individually exercised in this
check; iOS and visionOS were build-checked only. No Cast files changed.

## Abort during stalled storage

EEGQueuedRecordingStore now stops admission immediately on abort and schedules
file closure on its writer queue. Failure notifications use a separate serial
queue, so an overload notification does not wait for a stalled file write.
Statistics expose cleanupPending; the diagnostics view displays it. Starting a
new capture rejects with a specific error until cleanup completes. Already
rejected control operations also fail before waiting on the writer queue.

An in-flight write cannot be cancelled and may finish after abort. The file
remains incomplete without a summary. Notification is not a closure or durability
acknowledgement; consumers must inspect cleanupPending. A permanently stalled
OS write can leave cleanup pending indefinitely. Graceful finish and successful
trial/control writes still use synchronous barriers, and remain a limitation.

Two tests hold the actual output adapter's second write behind a semaphore.
They check overload notification before release, explicit abort returning before
release, pending cleanup, immediate rejection of restart/control/admission, and
incomplete output after release. Restart succeeds only after draining cleanup.
These are deterministic injected stalls, not physical disk or headset timing
qualification. Existing queue tests explicitly drain cleanup where they require
closed-file state because notification no longer implies closure.

Validation for this change: 105 Swift tests passed; macOS, iOS and visionOS native
builds passed. The new pending-cleanup message is build-checked, not interactively
verified against a physically stalled disk.

## Paced recording load qualification

An opt-in release-build test now exercises the canonical queued recording store
with paced synthetic samples plus events, then verifies every sample through the
full finalized-recording reader. The first harness attempt used the preview
replay default (1280 samples) and failed its stress-run count assertion; this was
a harness paging error, not evidence of writer loss. It was replaced with the
streaming full-reader before accepting results. See qualification/RECORDING_LOAD.md
for reproduction and measurement scope. This leaves asynchronous trial/finish
lifecycle integration and hardware qualification outstanding.

## Background final storage barrier

Normal Stop now ceases acquisition admission on the UI executor, sets a visible
finalizingRecording state, and transfers the final store.finish barrier to a
separate serial queue. No new capture or file import/export/replay is admitted
until completion returns to the UI. Success produces “Recording finalized”;
failure produces an explicit incomplete/uncertain result rather than the former
unconditional “Recording stopped” event. The canonical store still drains and
writes its normal statistics and summary; no second finalization implementation
or alternate file format was introduced.

Orderly app termination/background entry waits for that finalization queue,
preserving the previous shutdown durability barrier. Forced termination remains
incomplete, and a permanently stalled disk can still delay orderly termination.
Shadow-stop, trial interruption and checkpoint writes before this final barrier
remain synchronous; this change does not claim a fully asynchronous lifecycle.

A new core test transfers the finish control to a separate executor only after
admission ceases, holds an actual output write behind a semaphore, verifies
completion is not reported early, then releases it and verifies the finalized
sample and summary. Seven focused recording-queue tests passed. All three native
targets built. The app pending-state interaction has not yet been hardware-tested;
no participant trial or headset connection was started for this change.

## Ordered asynchronous operational events

Device metadata, stop checkpoints, annotations and shadow start/result/stop events
now use the same bounded admission queue as samples and transport events. Their
order is established on the acquisition executor; the final storage barrier
still drains all accepted inputs before producing a summary. Queue admission is
not durability. Marker feedback says queued, and shadow-result status explicitly
says recording queued. An asynchronous storage failure aborts the capture through
the existing generation-scoped failure handler; a failed finalization remains
an explicit failure.

Trial-plan publication and trial revision persistence retain their synchronous
contracts. Those controls still need an asynchronous acknowledgement lifecycle;
this change does not weaken their acceptance semantics or move them onto a
parallel evidence path.

The three shadow-verification tests now record through the queued store, with
its worker suspended while live inference processes the synthetic samples. They
release storage before finalization, then check exact run-boundary replay,
changed/missing output rejection, missing stop rejection, catalog/source pinning
and incomplete input rejection. All three passed. This is software ordering
validation; it is not a physiological or live Bluetooth timing qualification.

macOS, iOS and visionOS native builds passed. The new queued-status wording is
build-checked; no hardware run was initiated for this change.

## Acknowledged asynchronous trial-plan save

Trial-plan saving now enters the same bounded recording queue as samples with an
onPersisted completion. This specific event requests write plus filesystem
synchronize. The UI holds savingTrialPlan, disables duplicate saves and identity
edits, and publishes the plan only after successful completion for the current
recording generation while recording is still active. A stopped or replaced
recording cannot have a late acknowledgement enable its trials. Failure goes
through the existing storage-failure path.

The store's canonical appendEvent now has an optional synchronize flag; ordinary
events retain their previous write-only behavior. Queued events with onPersisted
request synchronization and deliver their completion on the notification queue.
Admission errors throw without a callback; admitted events discarded before
writing complete with failure. An in-flight write/sync may complete after an
abort, so success acknowledges that I/O only, not an active or finalized capture.
Neither filesystem synchronization nor the callback guarantees hardware power-loss
survival. Trial revision transitions remain synchronous and are the next pending
acknowledgement lifecycle work.

Three new tests hold synchronization behind a semaphore, verify no early success,
release it successfully or with a storage error, and verify a discarded queued
event reports failure. Ten recording-queue tests passed. These are injected I/O
boundaries rather than physiological or device tests.

Full validation: 110 tests, one opt-in load qualification skipped, zero failures;
macOS, iOS and visionOS builds passed. The plan-saving UI is build-checked only;
no fresh participant trial was performed.
