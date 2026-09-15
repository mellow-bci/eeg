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
