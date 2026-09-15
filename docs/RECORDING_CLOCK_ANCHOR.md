# Native recording clock anchor v1

New app recordings queue a `recording_clock_anchor` event after stream creation
and before device metadata/sample admission. Its `json` field contains
`eeg.recording-clock-anchor.v1` encoded by `EEGRecordingClockAnchor`.

| Field | Meaning |
| --- | --- |
| `receiptBefore` | Recording receipt-clock reading immediately before the host wall-clock call, seconds |
| `receiptAfter` | Same clock immediately after that call, seconds |
| `wallUnixSeconds` | Host `Date` value, seconds since Unix epoch |
| `localUTCOffsetSeconds` | Local time-zone offset at the observed wall time |
| `timeBasis` | `recorded_receipt_seconds`, identical basis to existing sample receipt timestamps |
| `wallClockAccuracy` | `unmeasured`; no NTP/device/UTC calibration is claimed |

The wall observation occurred somewhere between the two receipt readings. The
span is retained, not replaced by a midpoint. Conditional on no clock adjustment
or relative drift, receipt time `t` maps to the interval
`[wallUnixSeconds + t - receiptAfter, wallUnixSeconds + t - receiptBefore]`.
This interval captures call-order uncertainty only. It does not bound host clock
error, device sample latency or drift. `wallTimeBounds` exposes this conditional
calculation; acquisition and replay never apply it to recorded samples.

The model uses its existing uptime-minus-origin clock. The anchor is not a new
origin or a replacement for `stream_start.time`; a recording may start well after
connection. Capture remains local and raw timestamps/counters/calibration values
are unchanged. Invalid/nonfinite or reversed observations are rejected through
the existing recording failure path. No old file is modified or assigned an
inferred anchor. Raw BLE imports do not gain a hardware-time assertion merely
because they are imported now.

Validation: RecordingClockAnchorTests check call ordering, retained bounds,
conditional mapping and invalid/overflow rejection. The acquisition test checks
one serialized anchor in a completed native recording without a headset. The
selected eight clock/acquisition tests pass. This does not qualify real clock
synchronization, clock-change detection, sleep/wake drift or EDF interoperability.

Future export must decide how clock changes and discontinuities are represented;
this anchor is provenance, not permission to assume an exact acquisition timeline.

## Validated decoding

`EEGRecordingClockAnchor` now supports decoding its existing v1 JSON representation.
The custom decoder requires the stored schema, receipt-time basis and `unmeasured`
accuracy declaration to match exactly. It routes numeric values through the same
validated initializer used during capture; synthesized decoding cannot bypass
finite-value, nonnegative receipt, bracket-order or UTC-offset checks. Required
fields cannot be omitted or replaced by nulls or incompatible types. Unknown
additional JSON keys are ignored; they cannot replace the defined timing semantics.

The decoded object preserves both bracket endpoints, wall time and UTC offset.
It does not choose a midpoint, retime a sample, infer a missing anchor, verify UTC
accuracy or reconcile conflicting anchors in a recording. Consumers must still
validate the recording and select an explicit timing policy. This is a reusable
decoder prerequisite, not an implemented EDF export or a new user-facing feature.

Added tests cover roundtrip mapping before/inside/after the bracket, every missing
required field, incompatible provenance strings, reversed/negative bounds,
boolean/string/null numeric substitutes and invalid/fractional UTC offsets.

Validation on 2026-09-15: all four RecordingClockAnchorTests passed, followed by
successful macOS, iOS and visionOS builds. No physical clock or EDF reader was
used in this check.
