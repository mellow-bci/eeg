# EDF exchange implementation and qualification plan

Status: design only, 2026-09-15. No EDF export is implemented or enabled. Native
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
