# Recording load qualification

This opt-in native test uses the same EEGQueuedRecordingStore and
EEGRecordingStore as acquisition. It requires no headset, Cortex or participant.
It is a host/storage experiment with synthetic samples, not a physiological or
Bluetooth qualification. The normal suite skips it unless a report path is set.

Run from the eeg repository (choose a new report path for every run):

```sh
EEG_RECORDING_LOAD_REPORT=/tmp/eeg-recording-load.json \
EEG_RECORDING_LOAD_SECONDS=10 \
swift test -c release --package-path apple --filter RecordingLoadQualificationTests
```

Duration is configurable from 1 to 3600 seconds per rate. The two rates are 128
and 512 samples/second, each with one synthetic event per sample. The 512 rate is
stress input, not a supported EPOC X sampling mode. The test generates changing
ADC values and preserves exact original values; it does not apply the calibrated
voltage conversion or invoke the mental-command classifier.

Acceptance is zero test failures: successful finalization, exact sample count,
indices, counters, timestamps and ADC values on replay; all admitted inputs
written; no discarded input, failed writes or residual queued input. Timing is
reported, not gated by arbitrary CI thresholds. Admission duration includes input
construction and enqueue calls. Producer lateness measures host scheduling delay
against the requested monotonic schedule. Finish duration includes drain and
filesystem finalization. Queue statistics cover asynchronous input only.

The report is JSON, refuses to overwrite an existing file and records OS,
processor count, workload and timing scope. Record the source revision, build
configuration and test outcome alongside it. A generated report alone is not
proof that every assertion passed. Temporary recordings are removed after the
run. This does not measure process RSS, long-term memory stability, BLE traffic,
physiological accuracy, forced shutdown or a stalled physical disk.

## 2026-09-15 short run

Core source: ae44f898df2f0c17473494fe87f2efd9e48ac0cb, with the qualification
test added in this change. Configuration: `swift test -c release`, arm64,
macOS 26.6.2 (25G83), 28 logical processors. One selected test passed, zero
failures, 20.263 seconds. Raw results: recording-load-20260915.json.

| Requested rate | Samples compared | Admission p99 | Finish/drain | Peak pending inputs |
| --- | ---: | ---: | ---: | ---: |
| 128/sec | 1,280 | 0.103 ms | 1.190 ms | 2 |
| 512/sec synthetic stress | 5,120 | 0.092 ms | 1.257 ms | 4 |

Both runs had zero discarded inputs and failed writes. This is a ten-second
workload per rate on one host, with no concurrent Bluetooth or inference load.
It establishes short-run storage behavior only. No acceptance threshold for
scientific real-time operation or long-duration reliability is inferred.


## 2026-09-15 one-minute run per rate

Source: `f919df95f7b78775fc08e18e99fe5c41c36036f4` (only capability-matrix
text was edited during execution). Release Swift test on the same macOS 26.6.2,
28-logical-processor host. One selected test passed with zero failures in 121.332
seconds. Raw report: [recording-load-60s-20260915.json](recording-load-60s-20260915.json).
Reproduction uses the command above with `EEG_RECORDING_LOAD_SECONDS=60` and a
fresh report destination.

| Requested rate | Samples compared | Admission p99 | Finish/drain | Peak pending inputs | Maximum write |
| --- | ---: | ---: | ---: | ---: | ---: |
| 128/sec | 7,680 | 0.0884 ms | 0.431 ms | 28 | 102.797 ms |
| 512/sec synthetic stress | 30,720 | 0.0801 ms | 0.997 ms | 48 | 45.312 ms |

All 76,800 admitted inputs (samples plus synthetic events) were written with zero
discarded inputs or failed writes. Full finalized replay compared all sample
indices, counters, receipt timestamps, ADC words and electrode values. The queue
absorbed a roughly 103 ms write delay in this run; low admission percentiles do
not imply bounded disk latency. Producer lateness p99 was 3.850 ms and 0.925 ms,
respectively. No RSS, Bluetooth or concurrent classifier measurement was made.
One minute per rate still does not qualify long-session or crash reliability.
