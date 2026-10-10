# Offline parity verification — 2026-10-11

This checkpoint verifies independent bounded comparison kernels and authored host workloads. It does not establish full Cortex equivalence, physiological validity, Bluetooth capacity or production readiness. Working acquisition and the independent live trainer were not changed.

## Reproduction

Run from the eeg repository:

```sh
swift test --package-path apple --filter EEGCoreTests
swift test --package-path apple --filter ReferenceClassifierRebuildTests
EEG_RECORDING_LOAD_REPORT=/tmp/eeg-recording-load.json EEG_CONCURRENT_LOAD_REPORT=/tmp/eeg-concurrent-load.json EEG_RECORDING_LOAD_SECONDS=30 swift test --package-path apple --filter RecordingLoadQualificationTests
python3 tools/render_capability_matrix.py --check
```

Output paths are caller-selected; reports use synthetic samples and are not hardware captures. New binary traces are in the sibling timestamp-clock and signal-quality evidence directories, with pinned binary hashes. The numerical audit references previously captured bodies.

## Results and scope

- Initial full core suite: 516 tests, four skipped, no failures (`core-tests.log`).
- Expanded 519-test run: one authored fitter fixture rejected because it supplied 12 epochs below the traced feature-selection minimum of 20 (`core-tests-fixture-rejection.log`). The fixture was corrected to 20; implementation unchanged. All five fitter tests passed (`fitter-tests-corrected.log`). The final full suite passed: 519 tests, four skipped, zero failures in 156.433 seconds (`core-tests-verified.log`).
- Two optional paced host tests passed (`host-load-tests.log`): recording at authored 128/512 Hz preserved 3,840/15,360 samples; zero discarded inputs or failed writes. The 512 Hz case is a storage stress workload, not a supported headset configuration.
- Concurrent 30-second authored 128 Hz recording/inference preserved 3,840 samples and 15 inference windows matched replay. No discarded inputs or failed writes; p99 producer-to-inference availability delay 85.447 ms. This includes scheduling and is not isolated classifier latency.
- Whole-test-process resident memory sampled from 70,074,368 to a sampled peak of 71,892,992 bytes. Short sampled RSS does not establish sustained bounded memory or native application performance.

Default suite skips cover opt-in export, two optional host-load tests and external trained-profile comparison. The optional load checks were executed separately; missing Cortex profile/reference output remains a genuine comparison gate.

New software coverage includes clock anchors/rounding/counter history, adaptive rates, hardware-offset provenance, temporal reconstruction/CQ caching, quality fusion arithmetic, and the public fitter's rank-deficient input path. No proprietary model assets are bundled. Same-input trained-profile and signal-quality comparisons need local reference assets; prospective mental-command validity and physical lifecycle qualification remain outstanding. See `docs/REMAINING_PARITY_TODO.md`.
