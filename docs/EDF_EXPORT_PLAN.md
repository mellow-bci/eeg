# EDF exchange implementation and qualification plan

Status: receipt-layout preflight and explicit nominal-time segmentation planning implemented and tested, 2026-09-15. No EDF writer/export is implemented or enabled. Native
JSONL remains the preservation format. This work stays inside EEGCore and the
existing import/export UI, with no Cortex runtime dependency.

## Specification evidence

The [official EDF specification](https://www.edfplus.info/specs/edf.html) defines
fixed-width headers and ordinary signal records. The
[official EDF+ specification](https://www.edfplus.info/specs/edfplus.html), sections
2.1 and 2.2, extends this with annotations and discontinuous records. EDF+C denotes
contiguous records; EDF+D permits discontinuity. Ordinary samples must be equally
spaced within each record. Each EDF+ record includes annotation-channel timekeeping.
Header text is printable ASCII; ordinary samples are signed little-endian 16-bit
integers. Unknown patient identification fields use X. These are format rules,
not evidence of the headset's physiological accuracy or of vendor algorithms.

## Current-source findings and decisions

| Concern | Current source evidence | Required implementation decision / gate |
| --- | --- | --- |
| Absolute time | `RecordingStore.start` writes an ISO8601 wall time; `AcquisitionModel` uses uptime minus its connection origin for sample and marker receipt times. The file start and receipt-clock zero are not explicitly paired. | Add a versioned clock anchor for future recordings, with wall-time precision and uncertainty documented. Do not infer an exact absolute sample time from the file creation timestamp. Older files require an explicitly declared anchor or remain unsupported for absolute-time export. |
| Receipt vs acquisition timing | Samples preserve receipt time and counter continuity. Bluetooth batching/jitter does not prove irregular neural sampling. | Distinguish measured receipt time from any reconstructed nominal sample axis. Choose and record an explicit export timing policy; do not silently replace one with the other. |
| Gaps | Canonical processing breaks continuity and rejects invalid windows. | Segment only using validated continuity/configuration evidence. Do not fill missing samples with zeros or interpolation. EDF+D or separate files must retain the discontinuity; independent-reader behavior determines the supported packaging. |
| Fixed record length | Native recordings can stop at any sample or interruption. | Specify partial-final-record handling before coding. Padding is not an original measurement. No successful export may silently omit tail samples. |
| Units and integer range | Native samples retain unsigned ADC words and optional calibrated microvolts; CSV already rejects unavailable units. | Define reversible ADC signed encoding and quantify physical-header rounding separately from sample quantization. Validate per-channel calibration and out-of-range behavior; never clamp silently or invent calibration. |
| Annotations | Native files retain markers and trial revisions; some events have receipt times while others are metadata without a time. | Encode timed events using a documented annotation mapping. Preserve full original JSONL as provenance. Do not assign invented times to untimed events or claim EDF contains all native evidence unless a roundtrip proves it. |
| Completion | Native incomplete captures remain reviewable and distinguishable from finalized recordings. | Initially require finalized validated source for scientific exchange. Native export remains available for incomplete evidence. Any later partial-session exchange needs explicit annotation and qualification. |
| Scope | Existing hardware evidence is limited to the tested EPOC X configuration. | Verify channel order, configuration and nominal rate from source metadata. Unsupported hardware/configurations must fail explicitly. |

These are independent design requirements, not recovered Cortex parameters.
No acquisition reconstruction, resampling or new calibration is authorized by a
file-format choice.

## Ordered work

1. Add and test explicit recording-clock anchor provenance without changing raw
   samples, counters, decoder output or existing receipt times.
2. Implement a pure export planner over the canonical recording reader: derive
   validated segments, timing policy, channel/scaling metadata and annotation
   allocation. Report unsupported cases before creating a final output.
3. Implement a bounded writer with exclusive private output, partial-write cleanup,
   source-change detection and explicit header-width/range checks.
4. Roundtrip synthetic fixtures through an independent EDF+ reader. Check all
   channels and sample counts, signs/endian order, units, error bounds, event text
   and timing, discontinuities and tail preservation. A writer reading itself is
   insufficient qualification.
5. Validate files from the physically qualified EPOC X configuration against native
   measurements and existing reference evidence. Keep physiological claims separate.
6. Expose EDF in the existing format selector only for the verified subset; attach
   a provenance receipt and retain source JSONL. Test actual picker/export and
   reader interoperability, not only file creation.

Acceptance remains the capability matrix's independent-reader roundtrip gate.
Do not mark EDF implemented/tested based on this document, header generation,
synthetic waveforms alone, or successful opening without numeric comparison.

## Clock-anchor implementation checkpoint

New native app recordings now carry the explicit observation documented in
[RECORDING_CLOCK_ANCHOR.md](RECORDING_CLOCK_ANCHOR.md). Older recordings remain
without this evidence. The anchor preserves a bracket and unmeasured clock
accuracy; no EDF writer or automatic sample retiming is enabled. Drift,
clock-adjustment handling and independent-reader qualification remain necessary.

The anchor type now also validates stored v1 JSON on decoding; see the same
clock-anchor document. The canonical recording reader now validates a completed stream and returns
one pre-sample anchor or explicit missing evidence, rejecting malformed,
repeated and late anchors. The export planner remains pending; this provenance
check does not establish a calibrated absolute time axis.

### Format review follow-up (2026-09-15)

The official EDF+ specification, section 2.1.2, explicitly discusses a
discontinuous file containing one sample per ordinary signal per record and
instructs a zero record duration for that case. This is a possible preservation
strategy to investigate for irregular receipt timestamps and arbitrary tails;
it is not yet the selected export policy. It would describe receipt timing, not
prove neural sample timing. Reader support and scientific interpretation must be
qualified before enabling it. No padding, dropped tails or invented nominal
sample times have been introduced.

## Candidate receipt-layout preflight (2026-09-15)

`EEGEDFReceiptPlan.inspect` now implements a bounded preflight subset of step 2.
It does **not** write EDF files or approve their compatibility; `exportEnabled`
remains false, and no format option has been added to the app. Annotation
allocation, header serialization, physical scaling, and independent-reader
qualification still remain before the complete export plan/writer can be used.

The candidate is EDF+D with one sample per ordinary signal per data record and
zero record duration, as described in official EDF+ section 2.1.2. This represents
recorded receipt observations, not reconstructed neural sampling time. Repeated
receipt timestamps remain distinct samples; reader support for this case must
be established. No interpolation, padding, resampling or tail dropping occurs.

The inspector reads clock provenance and canonical analysis windows through
EEGRecordingStore. Windows are bounded containers here: invalid/partial windows
are not discarded. Their reasons are accumulated in `analysisWarnings`.
Unsupported device configuration or inconsistent raw ADC mapping rejects the
candidate. Missing microvolt values are reported but do not fabricate calibration:
this candidate concerns uncalibrated ADC encoding only. Original JSONL remains
necessary for raw packet/quality/event provenance.

It requires a finalized nonempty source, a valid pre-sample clock anchor,
nondecreasing receipt times and at most 99,999,999 samples (the eight-character
EDF record-count field). Hash and count agreement across both canonical reads
is required before returning any plan. Cancellation is checked before traversal,
per bounded window and before returning. This does not authenticate recordings
or guarantee detection of adversarial simultaneous mutation.

The result retains channel order, every sample count, repeated timestamp count,
per-channel unsigned ADC minima/maxima, source SHA-256 and the anchor's conditional
wall-time bounds at the first and last samples. Bounds retain call-order
uncertainty; clock drift and wall-clock synchronization accuracy remain unmeasured.
No midpoint is silently selected as an exact measurement time.

The proposed raw-word transform is `signed = unsigned - 32768`. It is exactly
reversible for all 65,536 UInt16 inputs without clipping. This is not a microvolt
calibration; no physical/header encoding is approved by the transform alone.

### Preflight tests

`EDFReceiptPlanTests` creates real finalized synthetic JSONL through the native
writer and traverses the canonical reader. Tests cover a three-sample partial
tail, duplicate receipt times, a gap/discontinuity, missing voltage metadata,
channel ranges spanning 0...65535, preserved original file bytes, clock bounds,
source hash and exhaustive reversible integer encoding. Missing anchors,
unsupported configuration, incomplete/empty sources and backwards receipt time
are rejected. No independent EDF reader is involved because no EDF is produced.

```sh
swift test --package-path apple --filter EDFReceiptPlanTests
./apple/build-native.sh all
```

This is new preflight functionality, not EDF feature parity, reader interoperability,
a calibrated timing axis or evidence of physiological accuracy.

Local preflight qualification: all three tests passed, all three native targets
built successfully. These builds do not establish physical-device or EDF-reader
compatibility.

## Independent-reader probe: candidate not interoperable in tested readers

On 2026-09-15, `tools/probe_edf_receipt_layout.py` generated minimal synthetic
EDF fixtures and tested **edfio 0.4.16** and **PyEDFlib 0.1.42**, with NumPy 2.0.2
on Python 3.9.6/macOS arm64. These optional validation packages were installed in
an isolated environment; they are not dependencies of the native app. No vendor
assets or human recordings were used.

### Follow-up: nominal 128 Hz exchange candidate

A separate synthetic EDF+C fixture with one sample per signal per record and
record duration `.0078125` (1/128 second) passed both readers. Both returned all
three signed samples and unsigned physical values exactly, record duration
0.0078125 seconds and total duration 0.0234375 seconds, without warnings. The
eight-character duration spelling fits the header. Assertions now cover these
sample and duration results in the probe.

[Full follow-up report](qualification/edf-nominal-reader-probe-20260915.json)
also reruns the earlier controls and incompatible layouts. This is a minimal
format fixture, not native exporter output or a qualified hardware timeline.

This opens an explicit **derived nominal timeline** exchange option for further
implementation. It does not preserve recorded receipt times as EDF sample times.
Before enabling it, the planner must separate continuity runs without filling
gaps, preserve every original sample including short tails, retain original JSONL
and clock evidence, and record the nominal timing policy and source hashes in an
exchange receipt. Event mapping and segment start uncertainty remain unresolved.
No existing receipt-layout preflight is silently reinterpreted, and no EDF export
option is enabled by this probe. Native acquisition and measurements are unchanged.

| Fixture | edfio 0.4.16 | PyEDFlib 0.1.42 |
|---|---|---|
| Continuous control, three 1-second records | Exact digital/physical sample roundtrip | Exact digital/physical sample roundtrip |
| Discontinuous positive-duration records at 0, 2, 4 seconds | Loads all samples; public duration reports 3 seconds, last record ends at 5 seconds | Rejects discontinuous file |
| Single-sample zero-duration records at 0, 0.01, 2 seconds | UnboundLocalError for sampling_frequency | Rejects discontinuous file |
| Single-sample zero-duration records at 0, 0, 2 seconds | Same UnboundLocalError | Rejects discontinuous file |

[Full errors, versions, hashes and measurements](qualification/edf-reader-probe-20260915.json).
The positive control is required to pass before candidate outcomes are interpreted.
The digital values -32768, 0, 32767 map exactly to unsigned ADC values 0, 32768,
65535 under the explicit test header; that is raw scaling, not microvolt calibration.
The discontinuous edfio duration observation concerns its public duration API;
this probe does not establish whether other internal APIs preserve TAL onsets.
Successful sample loading does not qualify an application-level timeline roundtrip.

This result blocks **this candidate layout's compatibility gate for these reader
versions**, not the entire EEG stack and not every EDF reader. The preflight
remains useful for source accounting, but must not be promoted to an enabled
writer on the strength of specification text alone. EDF+ section 2.1.2 permits
the special zero-duration representation; implementation support still matters.
PyEDFlib's source also lists an explicit discontinuous-file error:
[reader implementation](https://github.com/holgern/pyedflib/blob/master/pyedflib/_extensions/_pyedflib.pyx).

Reproduce with a fresh directory:

```sh
python3 -m venv /tmp/eeg-edf-probe-env
/tmp/eeg-edf-probe-env/bin/python -m pip install -r requirements-edf-qualification.txt
/tmp/eeg-edf-probe-env/bin/python tools/probe_edf_receipt_layout.py /tmp/eeg-edf-probe-output
```

The probe is a hand-built format fixture generator, not a second application
export path. It intentionally records unsupported outcomes and does not turn them
into successful exports. It does not exhaust EDF compliance, event annotations,
Unicode text, clock precision or real-headset interoperability.

Next decision: investigate a reader that exposes and preserves individual EDF+D
record onsets, or design an explicitly declared nominal-time EDF exchange plus
original receipt-time provenance. Do not silently relabel irregular receipt times
as regular neural sampling, drop tails, fill gaps, or remove the native originals
to make a reader accept a file. No alternative timing policy is selected here.

## Explicit nominal-time segmentation planner

`EEGEDFNominalPlan.inspect` now implements the next planning step for an explicit
alternative: **one continuous EDF+C file per continuity run**, with a derived
128 Hz sample axis within each run. This is our exchange design, not a recovered
device clock or proof of actual sampling accuracy. The original receipt-layout
plan retains its original semantics. Both planners still report export disabled;
no writer or new UI export option is supplied by this checkpoint.

The versioned timing-policy identifier is
`derived_nominal_128hz_per_continuity_run_v1`. The nominal relative last sample
time is `(count - 1)/128`, whereas file duration is `count/128`. Neither replaces
the recorded first/last receipt timestamps or the conditional wall-clock bounds
attached to each run. Runs must not be concatenated to hide intervening gaps.
No exact EDF header start time has yet been chosen from those bounds.

The implementation reuses `EEGEDFReceiptPlan` for source configuration, ADC mapping,
receipt ordering and clock preflight. It then reads canonical finalized records
to locate boundaries at the actual sample position, rather than rounding a
boundary to the existing 256-sample analysis window. A new run begins after a
transport recovery or metadata event, a discontinuity flag, an index/counter
gap, or a receipt gap greater than the existing canonical 0.5-second criterion.
This is conservative observed-evidence segmentation, not an assertion that
all unreported physical sample loss can be detected.

Samples observed while transport is unstable reject the entire nominal plan.
They are not dropped, and the native file remains available. Duplicate receipt
times remain separate samples. Counter wrap alone does not split a run. Metadata
refresh conservatively splits even if the supported configuration stays the same.
Each segment includes its source sample ordinal range, original sample indices,
receipt endpoints, count, start-time bounds and boundary reasons. The source's
analysis warnings remain attached, including missing microvolts and partial windows;
this raw ADC proposal does not invent voltage calibration or filter measurements.

Memory is bounded by a configurable positive `maximumSegments` (default 10,000).
Exceeding it rejects the plan before accepting another segment, including a short
final run; it never truncates output. The sample limit remains the receipt
preflight's EDF record-count bound. Cancellation is checked during traversal.
The source digest and total sample count must match the preflight, and segment
counts must account for every sample before any plan is returned.

Eight native tests passed, covering the earlier receipt preflight and five new
cases: continuous arbitrary tails; gaps within/across analysis windows; transport
and metadata boundaries; unstable samples; repeated receipt times. Tests also
check segment-limit rejection, counter wrapping, original-file preservation,
nominal duration versus final sample position, and exact sample accounting.
All three native builds (macOS, iOS Simulator and visionOS Simulator) passed.

```sh
swift test --package-path apple --filter 'EDFNominalPlanTests|EDFReceiptPlanTests'
./apple/build-native.sh all
```

Still required: bounded native writer, full source/provenance packaging, explicit
header-time policy, timed/untimed event treatment, independent-reader numeric and
annotation roundtrips, real-headset exchange qualification and actual UI export.
The earlier hand-built reader probe does not qualify output from this planner.
