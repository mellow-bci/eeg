# Native UI workflow qualification — synthetic data

Date: 2026-09-15. Application built from `d63f9de`, macOS native Debug target.
This is an observed UI exercise, not an automated UI test or hardware acceptance.
No Bluetooth discovery, audio cues, Cortex, or physiological recording was used.

## Executed path

1. Generate four synthetic recordings and a dataset using
   `TrainingDatasetTests.testRecordingsAndLabelsTrainNativeProfileWithoutEvaluationLeakage`
   with `EEG_NATIVE_EVALUATION_TEST_EXPORT` pointing at a new temporary directory.
2. Place exclusive, clearly named synthetic copies in the application's recording
   library and adjust only manifest recording filenames. Existing recordings remain
   unchanged. This step tests dataset loading, not the capture-import UI.
3. Restart the latest app, open Calibration → Open dataset manifest. Navigate the
   native Open panel using Go to Folder and select the synthetic manifest.
4. Train and save experimental profile. The UI reported 40 usable training windows,
   zero rejected labeled windows, and opened the profile for inspection.
5. Verify the saved profile against the fixture trainer: JSON objects match exactly.
   Participant `synthetic`, training sessions `a`, `b`, profile
   `72289065f2232fb489ea3d53e3b84d1d39bef6d7a723351cc52dd5d47a361927`.
6. Evaluate prepared dataset and expand Results by session. The UI showed 40
   evaluation windows, 5% pooled rejection, neutral rejection 0/20 and task rejection
   2/20. Sessions `c` and `d` each showed task rejection 1/10. These deliberately
   synthetic results are not estimates of human mental-command performance.
7. Export evaluation JSON through the native save panel. All JSON fields match the
   fixture evaluator except the intentionally changed manifest bytes/digest.
   The exported artifact is `native-ui-synthetic-evaluation-20260915.json` in this
   directory, SHA256 `f684b3bcf302b590e2111da8a6665b91195ddd148ac1a3a9387a398e07605ea5`.
8. Refresh profiles: the new profile appeared in the saved-profile library. Close
   profile and quit. Move only hash/content-verified synthetic additions out of the
   application library, retaining them in the temporary qualification directory.

The receipt is an output evidence artifact, not a recording archive. A fresh run
of the generator produces new recording IDs and file hashes; compare semantics,
not bytes, across regenerated runs. The source test and CLI verifier provide the
repeatable offline counterpart; the UI steps must be exercised separately.

## Remaining scope and observations

- The native dataset picker and synthetic train/evaluate/export route are now
  exercised interactively. Previous notes calling the picker unresolved are
  superseded for this macOS build only.
- Profile listing did not automatically refresh after training. Manual Refresh
  profiles worked; automatic refresh remains a usability improvement.
- No live acquisition, cue/review collection, retraining, iOS/visionOS interaction,
  accessibility audit, long-duration operation or physiological accuracy is proved.
- Control exposure was absent and visibly flagged. Command output stayed disabled.
- Existing wearer recordings and application processing settings were unchanged.

## Follow-up: automatic profile listing

The stale listing observed above is corrected: successful saves increment a
library revision, and the profile list reloads. If a list/inspection read is
already running, the refresh is retained and performed after it completes.
Manual refresh remains available for external filesystem changes.

Rebuilt all three native targets and repeated synthetic manifest import/training
in the macOS app. Started with an empty profile list; the saved profile's Inspect
button appeared automatically after the 40-window training completed, without
pressing Refresh profiles. Saved profile JSON still matched the original fixture.
Archived only verified synthetic additions out of the app library afterward.
No hardware or physiological claims follow from this UI check.

## Follow-up: session resampling controls (2026-09-15)

Exercised the actual macOS application while disconnected, using the same four
synthetic recordings and external profile described above. No headset connection,
recording, audio cue or physiological experiment was performed.

1. Enabled exploratory resampling and entered 1,000 draws, seed 42 and central
   percentage 95. Opened the exact dataset manifest through the native file panel.
2. Evaluation displayed 40 predictions and 5% rejection. Both class summaries
   displayed two sessions and incomplete cue evidence; no bounds were presented.
3. Exported the JSON through the native save panel. The parsed entire artifact
   equalled the native CLI output with the same inputs/options. Local receipt:
   `/tmp/eeg-ui-qualification-20260915/resampling-ui-evaluation.json`, SHA256
   `47516ec5db3fbcb3a49fde318ad07c5ea30f3f324295dc24ce349dbebc18109a`.
   This temporary path is an inspection record, not a durable fixture dependency.
4. Changed seed to 43. Previous metrics, resampling results and export control
   disappeared, preventing export of an old receipt under changed settings.
5. A first cancellation attempt arrived after completion and was not counted.
   A second attempt clicked Cancel evaluation while running; the UI returned
   “Evaluation cancelled; no new receipt was produced.” No new result appeared.
6. Populated text fields initially lacked persistent visible labels. Changed them
   to labeled content, rebuilt macOS/iOS/visionOS successfully, relaunched and
   visually verified Resamples, Reproducible seed and Central percentage beside
   their values. The accessibility tree also names each editable field. This is
   a focused check, not a full accessibility audit.
7. Closed the synthetic profile and quit. Archived only the four hash-verified
   synthetic library additions; both original user recording hashes remained
   unchanged. Source fixtures and exported receipts were retained locally.

These checks establish UI/CLI consistency and observable cancellation for this
synthetic workflow. They do not establish confidence coverage, valid cue labels,
mental-command accuracy, independent human sessions or production readiness.

## Follow-up: source coverage and neutral baseline (2026-09-15)

Exercised the macOS build at `d72ef1a` while disconnected, using the same
four synthetic recordings and external profile. No acquisition, audio cues,
hardware connection or physiological experiment was started.

1. Opened the exact profile through the native file panel. The app reported
   verified integrity and supported structure, participant `synthetic`, two
   training sessions, and command output disabled.
2. Evaluated the complete four-session manifest. The app showed training-source
   coverage `2 / 2`, 40 evaluation windows and 5% rejection.
3. Expanded Always-neutral baseline. The accessible UI displayed neutral recall
   100% for both rules and task recall 90% for the detector versus 0% for the
   baseline, together with the class-imbalance and correlated-window limitations.
   These are synthetic outcomes, not measured human performance.
4. Evaluated the manifest containing only evaluation sessions c and d. Coverage
   changed to `0 / 2`, explicitly naming missing original sources `a, b` and
   explaining that historical excerpt reuse cannot be checked against them.
   The 40-window evaluation remained available without claiming source coverage.
5. Closed the synthetic profile and quit. Moved only the four hash-verified
   synthetic library additions into a temporary archive. Both preexisting user
   recordings retained their exact SHA256 hashes.

This is focused native UI/accessibility-tree workflow verification. No new
export comparison or complete visual/accessibility audit was performed in this
follow-up. CI for `d72ef1a` also passed (run `34932076804`). Source coverage and
baseline comparisons do not establish independent sessions, physiological
validity, Cortex parity or production readiness.

## Follow-up: conditional trial comparison UI (2026-09-15)

Exercised the native macOS Debug build from `962f3a3`, disconnected throughout.
Code inspection confirmed Bluetooth initializes only on Find headset. No discovery,
connection, audio cue or recording was started. Used the prior four synthetic
recordings and external synthetic profile; original library files were untouched.

1. Opened the exact synthetic profile, expanded Conditional trial-schedule
   comparison and enabled its checkbox. The percentage defaulted to 80; its
   visible label and accessible name both identified per-trial eligible exposure.
   Inspected the actual screen layout. This was not a full accessibility audit.
2. Opened the fixture manifest through the native panel. While evaluation ran,
   the checkbox, percentage field and other evaluation settings were visibly
   disabled in the accessibility tree; Cancel evaluation remained available.
3. Evaluation returned 40 windows and 5% rejection. Expanded the new result
   disclosure: sessions c and d each displayed “Unavailable: Requires neutral
   and silent serial subtraction classes.” The no-automatic-significance,
   qualification and control statement was present. No comparison number was
   displayed for these unsupported classes.
4. Exported through the native save panel. The full UI receipt matched CLI output
   byte-for-byte for the same manifest, profile, recordings and fraction 0.8.
   Preserved receipt: `native-ui-association-20260915.json`; SHA256
   `075070a3eb9b0460e0e2e9baa586d9334dfc6d61a7a929b60c18ae77eedb8aac`.
   Both unavailable entries omit the result field. Raw source data is not embedded.
5. Changed the percentage from 80 to 85. Metrics, comparison results, prior export
   confirmation and Export evaluation JSON disappeared immediately. This verifies
   percentage-change invalidation; this pass did not separately exercise checkbox
   invalidation, invalid percentage submission or cancellation.
6. Closed the profile and quit. Hash-checked all original and synthetic library
   files, moved only the four synthetic copies to the temporary qualification
   archive and verified the library again exactly matched its two-file baseline.

This qualifies the focused macOS unavailable-result/settings/export path only.
The eligible-result display, all comparison failure messages, iOS/visionOS UI,
full accessibility and real physiological trials remain unqualified. Core tests
cover an eligible synthetic full recording-to-receipt result separately; that
is not an observed UI or hardware result. No Cast files were modified.


## Follow-up: eligible complete-plan comparison (2026-09-15)

Exercised the same macOS Debug production build from `962f3a3`, disconnected,
using the complete synthetic fixture exported by
`TrialAssociationEvidenceTests.testCanonicalRecordedEvaluationIncludesConditionalResultWithoutChangingInference`.
The fixture has 36,864 samples, a complete 24-trial journal, and a separately
trained synthetic profile. This is generated source data, not fabricated UI state.

1. Opened the fixture profile and enabled the comparison at 80% eligible exposure.
   Opened the fixture manifest. Settings were disabled while running and Cancel
   evaluation remained available.
2. The app reported 144 evaluation windows. Expanded results displayed session s,
   `705982 / 705982`, 80.0%, and “Conditional association only; exchangeability
   unverified.” The statement rejecting automatic significance, physiological
   qualification and system-control decisions was present. No task candidate was
   observed: the ratio is not a successful mental-command result.
3. The app also exposed 0/2 original training-source coverage and missing ordinary
   activity, blink, jaw and head-movement controls. The synthetic fixture does not
   satisfy those independent qualification gates.
4. Exported through the native save panel. The UI receipt was byte-identical to
   both the canonical test output and actual CLI output. Preserved synthetic
   receipt: `native-ui-eligible-association-20260915.json`; SHA256
   `68a8f7d6d42d46625c25d13685b15e954575114fefe23eb9ea0f0022eec2a18f`.
5. Unchecked the comparison checkbox. Evaluation metrics, comparison results and
   the export button disappeared. This verifies checkbox-change invalidation in
   addition to the preceding percentage-change check.
6. Closed the profile, quit, hash-checked all library files, and moved only the
   added synthetic recording to a temporary archive. Verified that the library
   exactly matched its original two-file hash inventory.

No discovery, headset connection, recording or audio cue was initiated. No Cast
files changed. This extends focused macOS software qualification to an eligible
complete-plan result, not hardware or physiological qualification. Cancellation,
all failure messages, full accessibility and iOS/visionOS interaction remain
outside this observed pass.

Reproduce the generated fixture and CLI comparison (use a new destination):

```sh
EEG_TRIAL_ASSOCIATION_TEST_EXPORT=/tmp/eeg-complete-plan-fixture \
  swift test --package-path apple --filter \
  TrialAssociationEvidenceTests.testCanonicalRecordedEvaluationIncludesConditionalResultWithoutChangingInference
python3 tools/check_trial_association_cli.py /tmp/eeg-complete-plan-fixture
```

The export option writes fixture files without overwriting existing files. It preserves the original
recording basename, needed by the trial journal. For UI qualification, temporarily
import/copy this synthetic recording into the local library without replacing any
file; open the exported profile and manifest, then compare the exported JSON with
`expected.json`. Preserve a library hash inventory and restore it after the pass.
The focused test passed (one test, 56.819 seconds); the CLI comparison and Python
syntax check passed. No production source changed in this follow-up, so the prior
three-platform build result is not claimed as a new build.


## Continuous complete-plan software check (2026-09-15)

The existing Replay and failure tests workflow now sets
`EEG_TRIAL_ASSOCIATION_TEST_EXPORT` during its native suite, then invokes
`tools/check_trial_association_cli.py` on that generated fixture. It reuses the
same native test, source recording, profile and receipt constructor; there is no
second inference implementation or fabricated UI result. The temporary fixture
is synthetic and is not uploaded by this change.

The local rehearsal used both native profile and complete-plan export environment
variables simultaneously. It passed 194 tests, with two opt-in paced/concurrent
load qualifications skipped and zero failures, in 121.559 seconds. The independent
Python loader accepted the exported native profile with experimental status and
control disabled. The complete-plan CLI check passed exact receipt equality,
source digest, all trial IDs/outcomes, exposure fractions and schedule accounting.

This is a local workflow rehearsal, not a claim that the revised remote job has
already passed. Check the GitHub run for the corresponding workflow revision.
No new UI, headset or physiological qualification was performed.


### Remote CI qualification result

[Run 34937415551](https://github.com/autonomy-cloud/eeg/actions/runs/34937415551)
completed successfully for exact revision
`6444526db996ef442d175878623f23b811b5bab8`. The job log confirms the native suite
ran 194 tests with two explicitly skipped load qualifications and zero failures
(257.416 seconds on the runner). Both profile export and complete-plan fixture
export were enabled in that same test step. The independent Python profile loader,
existing native CLI check and new complete 24-trial CLI equivalence check all passed.
The latter explicitly confirmed canonical receipt equality, source and outcome
accounting. Inventory consistency and the Python regression step also passed.

This upgrades the earlier local-rehearsal note to verified remote software evidence
for that revision only. It does not cover subsequent observer-entry/history changes,
physical headset input, prospective task labels, real artifact controls, UI timing,
load qualifications that were skipped, or production readiness.
