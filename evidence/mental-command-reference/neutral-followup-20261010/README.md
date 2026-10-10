# Scoring / neutral follow-up — 2026-10-10

Scope: static LLDB target/disassembly only on M4. No process launch/attach, no firmware mutation, no extraction of learned profile/model assets. Binary hash (in scoring-run.txt) is `cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`.

## Implemented bounded arithmetic

`ReferenceCommandScoring.swift` is internal and not enabled on existing profiles. It reproduces the post-lowpass **normal inference** numerical branch on a supported finite probability vector. Its input is already filtered; this avoids asserting the still-unverified matrix filter axis and production call/reset cadence. This is static-body-backed arithmetic plus synthetic unit tests, **not executed vendor-output parity or physiological validation**.

| Behavior | Body evidence |
|---|---|
| Neutral numeric identity = 1 | `getCurrentClassReference` checks initial 1 at 0x100b35ab0–ab8; ScoringManager checks/removes initial 1 at 0x100b5c9e0–ca24. `getActiveActionsNotIncludeNeutral` excludes value 1 (0x100b30bb8). |
| Rows = [neutral, nonneutral actions in current reference order, added neutral] | ScoringManager constructs first 1 at 0x100b5d248 (allocation slow path also 0x100b5d2c0), copies rows-2 action IDs at 0x100b5d368–d500, appends final 1 at 0x100b5d514. Copies IDs into appended sort column at 0x100b5d78c–7a4. |
| Profile activation integer A | `cognitiv-activationThreshold` read/toInt 0x100b5cb64–b9c. t = ((3.5-A)*0.55/7)+0.275 at 0x100b5cbd8–cc10. Constants bit patterns 0x3fe199999999999a and 0x3fd199999999999a. Code checks resulting t in [0,1]. Our supported A is 0...7; no claim this is complete vendor API range. |
| Nonneutral maximum gate | Filter virtual call 0x100b5d674–688; rows 1 through rowCount-2, column0, inclusive `subset` at 0x100b5d690–6ac then max at 6b4; if max<t outputs neutral/zero and clears latch. Inclusive subset bounds confirmed in subset.txt 0x1021399d4 / a14. |
| Sort descending probability and retain row identity | SortingTxf(0,0,1) call 0x100b5d700–70c; constructor stores args at object +8,+12,+16. Inner apply maps +16==1 to literal `descend` at 0x1021420ac–c4. Outer sorts rows for +12==0. Top identity read at 0x100b5d830–844. |
| Margin power | If top action==1, initial margin=0; otherwise top probability minus second probability at 0x100b5d858–880. p=max(0,(margin-t)/(1-t)) at 0x100b5d884–894. Finite supported [0,1] inputs imply p<=1; reference does not require added upper clipping here. |
| Hysteresis | 0x100b5d8a0–8fc: p==0 clears latch; p<0.3 while latch false outputs zero; p>=0.3 sets latch; positive subthreshold values pass when already latched. Constant 0x3fd3333333333333. Zero final power forces identity1 at 0x100b5d900–904. Latch is manager-wide; no evidence for per-action latch. |
| Initialization | ScoringManager::init clears +0x10 latch at 0x100b5c108. Full event/profile reset cadence not reconstructed. |

Own API policies, not recovered vendor behavior: reject 0 or >4 actions, duplicates, action IDs <=1 or outside Int32; require values.count=actions.count+2 and finite values in [0,1]; reject invalid inputs and clear latch; caller explicitly resets on recipe/profile change. The four-action support bound avoids overrunning the reference's four-integer local scratch region; semantic validity of each positive action ID is the caller's responsibility. No assertion of command labels (push/pull/etc.). Ties cannot yield positive margin for t>=0, so unstable sorting tie order does not affect the supported output.

## Training and neutral lifecycle — not implemented as recovered behavior

`runAutoSamplingNeutral` reads profile fields `cognitiv-trainingControl` and `cognitiv-autoSamplingNeutral`. A boolean data-availability argument and nonempty matrix gate collection (0x100b31764–70); paired matrix lists collected at manager +0x80/+0x98. On completion, list count is compared to manager integer +0xb0 (0x100b317fc–1808). Its source/value is not yet traced and must not be invented. Successful completion calls buildClassifier(profile,true, classifier-at-+0x670), then saveClassifier. Failure calls clearClassifier, saves the cleared classifier, and clears ErrorSetClassifierBank; updates trained actions and emits completion. Neutral collection is therefore training/lifecycle work, not interchangeable with the inference neutral fallback row.

ScoringManager run also handles events, accumulates true/false-force skill metrics, and on some event codes suppresses output or carries previous output through empty matrices. Those paths are preserved in raw evidence but not implemented here because enum and caller condition semantics are not fully established.

## Asset/config dependency found

`loadSensitivityFromConfig` normalizes headset type, finds that type in manager map at +0xb88, and copies its QList<double> to +0xb90 (0x100b39248–2d8). The map contents are **not constants in this routine**. An exact end-to-end reference recipe requires the matching configured sensitivity list and its use-site semantics. No config values or proprietary model assets were copied. This establishes a parameter dependency; it does not establish that the dependency is an inseparable proprietary trained asset.

The scoring/neutral-margin stage implemented here itself requires no vendor model weights. Full reference comparisons still require equivalent independently produced or explicitly authorized parameter fixtures and reference outputs. Function names alone are not evidence of recovered training algorithms.

## Reproduce tests

```
swift test --package-path apple --filter ReferenceCommandScoringTests
```

2026-10-10: 4 tests pass, covering row identity, both neutral entries, activation setting endpoints, threshold/margin, activation hysteresis and reset, ties and fail-closed invalid input. These are independent expected-value fixtures derived from the disassembly; they are not recordings of executing Cortex.
