# Offline qualification and remaining hardware gates

`tools/qualify_recording.py` evaluates a **single recording's transport evidence**.
PASS is explicitly scoped. It never certifies the product, physiology, cognition, clinical
use, independent headset startup or agreement with Cortex. Use `compare_paired.py` for the
separate full-vector Cortex comparison.

```sh
python tools/qualify_recording.py archive/current-state/epoc-cortex-retest-20260915-01.jsonl
python tools/qualify_recording.py archive/current-state/epoc-cortex-retest-20260915-01.jsonl --allow-startup-errors
```

The first command intentionally fails the strict startup policy. The second explicitly
accepts startup anomalies, reports them, and passes the narrower transport criteria.
Exit codes: 0 PASS, 1 failed criteria, 2 invalid invocation or unreadable input. JSON report
goes to stdout; it includes the complete input SHA-256 and chosen thresholds. No hardware,
network service, account state or recording modification occurs.

## Checks and interpretation

| Check | Definition |
|---|---|
| Syntax/completion | Every line is an object with an event kind; exactly one summary must be the last event. This establishes a writer completion record, not independently proven crash durability. |
| Counters | Recompute modulo-128 counter continuity per epoch instead of trusting the stored `continuous` flag. |
| Timing | Reject backwards/nonfinite sample arrival clocks and gaps exceeding 0.5 seconds. Multiple samples in one BLE notification share a timestamp. |
| Startup classification | Events before the first stable indication are startup issues. Once readiness has occurred, all later recovery/errors remain post-readiness, including reconnection recovery. |
| Duration | Sum within-epoch sample arrival spans. Default minimum 120 seconds. This does not prove the headset clock's absolute accuracy. |
| Stable evidence | Sum sample arrival spans by epoch and stable segment. Default minimum 10 seconds; require calibrated consumer eligibility for reported stable samples. |
| Arrival rate | Per epoch, `(samples - samples_in_first_arrival_batch) / arrival_span`. Default expected 128 Hz with 2% tolerance. Host arrival timing is not a device timestamp. |
| Summary consistency | Recount samples, stable samples and decode errors; compare with summary. Require no reported fatal/connection/interruption failure. |
| Session scope | Exactly one sample epoch. Reconnect experiments are intentionally not qualified as uninterrupted sessions by this CLI. |
| Startup policy | Default rejects all startup issues; `--allow-startup-errors` exposes an explicit narrower qualification. |

Unknown event kinds are counted but do not themselves fail qualification, allowing additive
metadata. This checker is not a full schema validator or cryptographic packet integrity
validator; AES-ECB transport does not provide authenticated payload integrity. It streams
input rather than loading raw sample arrays, retaining aggregate state per epoch/segment.

## Current artifact result

Verified with the 2026-09-15 implementation against
`archive/current-state/epoc-cortex-retest-20260915-01.jsonl`:

- SHA-256 `049cbc67e76c266af74eb59dfeee14b5258b21eb7cd9bdb2ea6b844648ae3ca7`
- 15,374 decoded / 15,108 stable samples.
- 120.016587083 s total and 117.962098208 s stable arrival span.
- 128.082295736 samples/s observed arrival rate.
- Startup: 2 decode errors, 2 counter gaps, 4 recovery transitions. These counts overlap causal events and must not be summed as independent lost packets.
- No post-readiness issues detected by this checker.
- Strict FAIL; explicit startup-tolerant PASS. Neither is whole-product certification.

Eight targeted tests cover contiguous completion, truncated capture, startup policy,
post-readiness recovery, deleted samples, malformed/trailing events, backwards clocks and
invalid thresholds. Run `python -m unittest discover -s tests -p test_qualification.py -v`.

## Hardware gates that unattended software work cannot substitute

| Gate | Needed evidence | Completion condition |
|---|---|---|
| Cortex-free start | Physical headset powered on with vendor processes disconnected | Repeated discover/start/stop/restart from our app without vendor initialization. |
| Long session | Charged headset and stable placement | At least 8 hours across battery-supported sessions with declared breaks; measured memory/storage/loss and no hidden gaps. A single battery may not cover the target duration. |
| Hardware interruption | Deliberate headset off/on, out-of-range, Bluetooth interruption | Explicit gap state, no stale sample delivery, recovery and new segment boundaries. |
| Sleep/wake | User-approved Mac sleep during capture | Predictable stop/reconnect, retained file integrity and no fabricated continuity. |
| Contact classification | Prepared sensors, controlled contact changes and reference measurements | Per-electrode labels validated across good/poor/disconnected conditions; raw equivalence alone insufficient. |
| Fresh installation | Clean Mac user/device permissions | Install, grant Bluetooth, acquire and export without development environment or vendor app. |
| Intent classification | Consenting participant sessions with labeled trials and held-out days | Predetermined sensitivity/false-activation/idle criteria; physiological artifacts explicitly distinguished. |

The native target is SwiftUI on macOS, iOS and visionOS. Each needs independent
CoreBluetooth discovery/permission/lifecycle tests on physical hardware. Apple BCI HID
qualification covers decoded accessibility commands, not EEG sample transport; neither
a Mac Python capture nor a Swift simulator build validates iOS/visionOS hardware support.

Storage, consumer delivery and installer code can be built and fault-tested in parallel.
Physical actions and participant experiments need actual hardware conditions and must never
be replaced by replay tests while reporting live success.

### Consumer shutdown deadline regression

A hosted CI run exposed a scheduler-dependent error classification: `close()` could
resume after the callback deadline and report generic shutdown timeout before checking
the elapsed callback deadline. The final shutdown path now checks callback/queue
expiry first. A deterministic test skips the wait loop with an expired callback and
asserts explicit `sample_consumer_timeout`, undelivered count and bounded shutdown.
The full local suite passed 120 tests with ResourceWarning treated as an error. This
is software fault-injection evidence; no new hardware qualification is claimed.
