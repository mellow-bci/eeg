# Runtime algorithms and failure semantics

Implementation: [stream.py](../stream.py).

## Connection and metadata

The selected CoreBluetooth ID is resolved against already-connected peripherals using the EPOC service UUID. A matching peripheral is passed directly to Bleak with its central-manager delegate; this avoids waiting for advertisements from a device already connected by Cortex. Otherwise Bleak performs normal lookup. Omitting the ID uses an EPOCX name advertisement filter; deployments should prefer an explicit ID to avoid ambiguity.

`live()` supports bounded connection attempts and exponential backoff `min(2**attempt, 10)` seconds. A client connection has a 15-second timeout. Configuration read has a five-second timeout; failure is logged and raw ADC acquisition may continue without calibrated consumer eligibility. Each successful configure creates a new decoder and epoch.

## Packet processing and stability

For each EEG notification:

1. Persist original UUID, bytes as hex, arrival time and epoch.
2. Reject non-finite/backward host arrival clocks as acquisition failures.
3. An arrival gap over 0.5 seconds resets readiness, even if modulo counters appear continuous.
4. Decode/validate both EEG records. A protocol rejection increments error counts and resets stability.
5. Any sample counter discontinuity resets stability.
6. Require **at least 256 subsequently counted contiguous samples AND at least two seconds of host time** before marking stable. The initial qualifying packet establishes the time baseline; it is not included in the counter increment, so the exact warmup sample count can exceed 256.
7. Increment `stable_segment` on each transition into stable state.
8. Persist all samples. Deliver only `transport_stable AND voltage_divisor is not None` samples to the optional consumer.

`check_freshness()` also revokes readiness during silence after 0.5 seconds; it does not wait for the next packet. The live loop checks about every 0.1 seconds. No notifications for five seconds triggers interruption/reconnect handling. These are conservative transport policies, not a scientifically derived EEG quality metric.

## Sample indices and timing

`index` is decoder-local and resets on connection. `stream_index` increases across epochs. `stable_segment` changes after recovery. The two samples in a notification share host arrival time and have `notification_slot` 0/1. Neither sample is assigned an invented device clock timestamp. Counter modulo 128 wraps approximately each second at the observed rate and cannot independently measure long gaps.

## Consumer and failures

`Pipeline(output, sample_sink=callable, consumer_queue_size=1024, consumer_timeout=0.5, consumer_shutdown_timeout=1.0)` optionally delivers stable, calibrated sample copies to one dedicated daemon thread in FIFO order. The producer never waits for the callback. Record writes remain exclusively on the acquisition thread. Consumers must be thread-safe and use epoch/segment boundaries; a queued sample describes eligibility when captured, not current headset readiness.

Queue insertion is nonblocking. Overflow is fatal (`sample_consumer_overflow`): queued backlog is aborted, never silently treated as delivered. Both queued age and callback elapsed time are bounded by `consumer_timeout` in monotonic seconds. A queued sample older than that budget is not started (`sample_consumer_stale`). Callback exceptions (`sample_consumer_failed`) or a callback exceeding its budget (`sample_consumer_timeout`) revoke readiness. `packet()`, `configure()`, `check_freshness()` and `finish()` observe worker faults; the live loop checks about every 0.1 seconds, including silence. No Bluetooth retry can repair these failures. The sink receives a deep copy and cannot mutate the recorded sample.

`finish()` requests a FIFO drain, checks health, and waits at most the shutdown budget. Unfinished work produces `sample_consumer_shutdown_timeout`. An existing acquisition fault aborts backlog. The summary adds `consumer_delivery` with submitted, completed (`delivered`), undelivered counts, worker-alive status and the first worker error; it is null when no consumer is configured. These counters are a snapshot at close. A failed or timed-out callback may already have performed external side effects, so callers must not retry actions from these counters.

Python cannot safely terminate an arbitrary hanging callback. A timed-out worker is a daemon and cannot hold process exit open; no subsequent callback starts after it observes abort, but an already-running callback can finish later. Hard isolation from arbitrary native code or untrusted consumers requires a separate process and remains a release gate. This implementation bounds acquisition waiting and memory, not arbitrary callback CPU/native-code execution. Storage write/flush errors remain fatal, and a storage failure may prevent final summary persistence.

## Storage, ownership, shutdown

- Exclusive-create JSONL, mode 0600; an existing file is never overwritten.
- `--seconds 0` runs until operator stop or an explicit failure; finite positive durations are supported without the former one-hour cap. Duration is per connection attempt. This does not remove storage capacity limits.
- Default 512 MiB byte budget, configurable by `--max-bytes`; exceeding it fails explicitly rather than truncating or dropping silently. No automatic rotation is implemented.
- Flush each event; fsync on successful final summary. Power-loss durability of every individual event is not guaranteed.
- `DeviceLease` uses an OS advisory flock keyed by the normalized explicit device ID. It protects cooperating reader instances, not Cortex or unrelated apps. Discovery and explicit IDs are not globally reconciled.
- SIGTERM follows Ctrl-C: revoke stability, write `shutdown`, then summary where storage permits. Fatal storage failure may prevent the summary from being written; absence of a summary must be treated as incomplete.
- Exit is zero only for `capture_clean`; recovered startup anomalies keep the run non-clean. Normal reconnect recovery must not erase error history.

## Known operational edges

Research callers that invoke `live()` directly do not automatically receive the CLI lease/SIGTERM wrapper. There is no service installer, rotation/retention daemon, signed app bundle or certified permission onboarding. These remain explicit release work, not completed by documenting them.
