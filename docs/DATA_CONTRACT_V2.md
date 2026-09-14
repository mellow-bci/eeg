# Canonical EEG contract v2

`processing.contract` is the explicit adapter boundary. Existing files remain
unchanged: Python `eeg_adc` events and Swift `eeg-native-v1` envelopes adapt into
one frozen `CanonicalSample`. `iter_event_samples(events, source_id)` accepts live
ordered event iterators; `iter_samples(path)` uses the same adapter with bounded
4 MiB JSONL lines, SHA-256 source identity and required final summary. File mutation
is rejected when processing finishes. A caller must exhaust and successfully finish
the reader before publishing an offline result.

The canonical channel order is AF3,F7,F3,FC5,T7,P7,O1,O2,P8,T8,FC6,F4,F8,AF4;
`CHANNELS` in the implementation is authoritative.

Each immutable sample preserves index, modulo-128 counter, host arrival time,
connection epoch, stable segment, explicit transport stability, continuity,
14 ADC values, optional uncentered microvolt values, configuration identity and
source identity. No missing channels, invented timestamps, interpolation, automatic
unit fallback, or physiological interpretation is supplied. For observed config
`018000102010`, supplied microvolt values must match ADC/7.8. Unknown configurations
remain identifiable but cannot produce valid analysis windows.

Python samples use their explicit epoch/stability fields and stream-start metadata.
Native recordings obtain configuration from `device_metadata` (direct UUID fields
or imported `metadata_json`), and stability exclusively from preceding chronological
`transport_status` events. Starting a native file establishes one connection epoch;
missing status remains unstable. A native recovery followed by stable starts a new
stable segment. Other schemas and unit names fail closed.

`processing.windows.iter_windows(samples)` produces fixed **256-sample**, nominal
128 Hz, nonoverlapping windows. Every original sample belongs to at most one window;
partial tails are emitted invalid. `Window` contains samples, valid, reasons, start,
end and id. Start/end are actual first/last arrival timestamps, not interpolated
sample-clock boundaries. Reasons cover unstable transport, missing epoch/segment,
source/segment boundary, counter/index gaps, clock reversal or arrival gaps over
0.5 seconds, unsupported configuration, absent microvolts, invalid ADC and observed
rate outside 120–136 Hz. These are transport/configuration gates, not validated
physiological artifact thresholds. Artifact checks belong to the feature layer.

Feature extraction, training and evaluation must consume only valid windows through
this interface. Preserve invalid reasons and counts in reports. Replay does not
become a second preprocessing implementation. Historic calibration scripts remain
research evidence and are not an alternate canonical production workflow.

Synthetic correctness tests cover cross-format equality, immutability, missing
status, imported metadata, segment transitions, independent windows, invalid units,
configuration/missing samples and file completion/counts. ADC word mapping is checked when wire words are present; integer ADC values are required. Gaps at window boundaries invalidate the following window. They provide no physiological
validation claim.

`windows_from` carries a source/epoch/segment continuity identity into proposals.
Detector persistence resets when this identity changes, even when host times appear adjacent.
