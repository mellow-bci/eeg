# Data contract

One JSON object per line; binary values are hex. Treat recordings as sensitive.

| Event | Meaning |
|---|---|
| `capture_cycle`, `connection_attempt` | Bounded session/reconnect intent |
| `stream_start` | Source, host-local device ID, UTC configure time, raw metadata, epoch |
| `metadata_read_error` | Configuration unavailable; no guessed voltage conversion |
| `ble_notification` | Original byte payload and monotonic arrival offset |
| `eeg_adc` | One decoded sample, raw words, labeled electrodes, counters, flags |
| `auxiliary_raw` | Twenty-byte auxiliary record retained without motion calibration |
| `decode_error` | Entire notification rejected structurally |
| `transport_status` | `recovering` or `stable`, with reason/time |
| `connection_status`, `connection_error` | Connection outcome and failure |
| `shutdown` | Operator-stop marker where graceful shutdown succeeded |
| `summary` | Counts, epochs, rate estimates, errors, stable counts, clean/fatal flags |
| `audio_cue`, `phase_cue_onset`, `test_phase`, `test_outcome` | Research cue timing, not measured participant compliance |

## EEG fields

- `adc_words`: 15 little-endian unsigned 16-bit values.
- `electrodes_adc`: 14 electrode-name-to-ADC values using the verified map.
- `eeg_adc`: wire-order values excluding word 7; do not confuse with electrode output order.
- `other_word_7`: raw CQ transport word, not an EEG electrode.
- `electrodes_microvolts`: optional `ADC/7.8`, uncentered; only the exact supported configuration enables it.
- `counter`: 0…127; `continuous` compares against predecessor modulo 128.
- `received_at`: monotonic notification arrival offset; `notification_slot`: 0/1.
- `epoch`, `index`, `stream_index`: connection-local/global identity.
- `transport_stable`: continuity/freshness gate only.
- `consumer_eligible`: stable plus supported voltage configuration; not physiological eligibility.
- `stable_segment`: integer when stable, otherwise null; never concatenate across changes.
- `record_flag`: preserved high header bit with no unsupported interpretation.
- `integrity_verified:false`, `physiology_validated:false`: intentional claims boundaries.

A `capture_clean:false` run can contain many valid stable samples. A true clean flag is not proof of good scalp contact, absence of artifacts, cryptographic authentication or production readiness.

Historical captures predate later fields. The original archive preserves them unchanged. Consumers must not fabricate missing readiness/calibration fields when importing old data.
