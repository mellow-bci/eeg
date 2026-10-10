# Consolidated offline continuation verification

This continuation contains default deployed-recipe/scalar reconstruction, current type-7 CQ mapping/calibration, and raw timed/reviewed training plus independent durable save/reload/retraining. Sources and tests are internal comparison components; working acquisition and live trainer are unchanged.

## Reproduction

From the eeg repository:

```
swift test --package-path apple --filter 'Reference|Decoder'
swift test --package-path apple --filter EEGCoreTests
python3 tools/render_capability_matrix.py --check
```

The first command completed 279 tests, two skips, zero failures on M3. Skips explicitly require a native reference export destination and an external matched Cortex profile/output fixture. Neither becomes a pass or an exact-parity claim. The final full EEGCoreTests command completed 471 tests, four skips, zero failures in 160.458 seconds. See reference-tests.log and core-tests.log for exact per-test outcomes; synthetic numerical success is not physiological or same-model vendor equivalence.

Raw workflow tests fit authored raw samples, atomically persist an owned bank/recipe/model, close/reopen, compare inference, append new training and publish a new revision. Timed collection invokes the existing lifecycle using separate monotonic clocks; delay/duration/minimum gates and wall-clock rejection are tested. Reviewed epochs use a separately labelled independent path. Commit failure/rejected fit/malformed bank/version/resource checks remain observable. Other store tests cover interrupted publication and restart. SQLite/AES-GCM storage is our own format, not the Cortex database/file format.

The initial authored fixture failed the existing PCA selection rule because over 99% of its variance collapsed into one component. The fixture was revised to include independently varying channels and a smaller class offset; fitting rules were unchanged. Failure and diagnosis logs remain in ../raw-training-store-continuation-20261011/. No failing vendor comparison was hidden by this fixture change.

An archived real 128Hz recording traverses the default 98-power-feature recipe deterministically. Its quality and intent labels are unknown, so quality is deliberately rejected and it never establishes a command. CQ arithmetic/configuration tests use authored values; constructor initial states are not measured readiness.

## Remaining evidence

Current loaded Cortex overrides, synchronized CQ/contact transitions, and same-input/same-trained-profile stage outputs remain unverified. The previously checked training-attributes store was empty. Prospective participant labels and session holdouts are required for physiological reliability. No vendor learned assets were used or bundled. A trained profile and matching outputs would be optional local-only reference inputs, not a product runtime dependency. The previously identified embedded salt remains excluded and is unnecessary for owned storage.
