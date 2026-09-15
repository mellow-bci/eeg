# Experimental native EDF exchange writer

2026-09-15. `EEGEDFNominalExport.write` now produces native output from the
explicit nominal-time planner. The app's export selector remains native/CSV only.
This writer is experimental: hardware exchange, native marker translation,
interactive export and complete reader timing compatibility remain unqualified.

## Package and independent design

The destination must be a new directory. It is created exclusively with mode 0700;
files use exclusive creation with mode 0600. Existing directories/files are never
overwritten. Failure attempts to remove only the newly created package; cleanup
itself can fail on unavailable storage. A composite `CleanupFailure` preserves
both errors and identifies the partial package when removal fails. No crash-atomic
directory publication or power-loss guarantee is claimed. A package is complete
only after the receipt has been written, synchronized, closed and atomically
renamed from `.provenance.pending` to `provenance.json`. The same-directory rename
uses Darwin `RENAME_EXCL`; unsupported filesystems fail rather than silently
falling back to a nonexclusive publication. Directory durability across power
loss is not qualified.

The writer copies the original JSONL using the existing native archive service,
replans the copy and checks its digest against the initial plan. EDF generation
streams the copied source through the canonical finalized reader and checks its
digest and total/segment counts again. Input samples and acquisition are unchanged.
Memory holds one small data record, one output hash, and bounded segment metadata;
the planner's configurable segment cap is retained. Cancellation is checked in
preflight, per record and before the receipt. Write failures propagate rather
than returning successful truncated packages. Cleanup failure is explicitly
reported alongside the original error; a remaining pending receipt is not a
completion marker, even if its JSON is fully parseable.

Each run becomes `segment-NNNNNN.edf`, with 14 raw channels in canonical order and
one EDF Annotations signal. There is one sample per ordinary signal per record,
record duration `.0078125`, and no partial-tail padding. Digital values are exactly
`unsignedADC - 32768`, little endian. Physical min/max are 0/65535, with blank
dimension to declare uncalibrated ADC. No voltage calibration or signal filtering
is invented. The header identifies unknown participant fields as X.

The **chosen derived start** is the lower conditional wall-time bound at first
receipt. This is an explicit exchange convention, not a measurement of neural
acquisition time. Header civil time uses that value's whole-second floor and the
stored UTC offset; the TAL carries the fraction plus `sampleOrdinal/128`, rounded
to eight decimal places. Years outside 1985–2084 reject rather than wrap. Bracket
uncertainty, unmeasured synchronization, clock drift and Bluetooth delay remain
documented. Segment gaps are not filled or compressed into one continuous file.

Each EDF contains timekeeping plus a notice at its first sample:
`Derived nominal 128 Hz; see provenance.json`. **Native markers and trial events
are not translated into EDF annotations.** The mandatory original JSONL preserves
their text (including Unicode), timing and provenance. The receipt explicitly
describes this limitation instead of silently implying annotation equivalence.

The receipt records source and EDF hashes, sizes, sample ranges/counts, original
receipt endpoints, boundary reasons, clock anchor/bounds, selected start,
configuration policy, analysis warnings and compiled core source identity.
`hardware_validated` and `reader_qualified` remain false. A checksum binds bytes;
it does not authenticate a recording or establish its scientific accuracy.

## Tests and independent-reader findings

Native tests generate 263 synthetic samples × 14 distinct channels, split into
129/134-sample segments with a gap. They check every ADC value, signs/endian order,
full source preservation, file hashes, permissions and byte-identical repeated
exports. An unsupported date failure removes the new package; an existing
destination/sentinel survives untouched. Together with the planner/preflight,
10 tests pass. This is not a hardware or disk-fault endurance test.
Final macOS, iOS Simulator and visionOS Simulator builds and the independent
compiled-source identity oracle also passed.

`tools/qualify_native_edf.py` reads actual native writer output using **edfio 0.4.16**
and **PyEDFlib 0.1.42**, not a writer-generated decoder. Both independently recovered
all 3,682 signed/physical ADC values exactly, correct labels, blank units, 128 Hz,
both full durations and the timeline notice, without warnings.

Timing is **not fully qualified**. edfio's public start datetime matched both
derived fixture starts within one microsecond. PyEDFlib's public `getStartdatetime`
reported errors of -0.009 and -0.016031 seconds. Inspection of the installed method
shows it divides `starttime_subsecond` by 100 to obtain microseconds; the first file
returned 99999 for that raw value, while its TAL onset is about 0.01 seconds.
This is a bounded observation of this version/API, not a claim that every reader
or underlying C API loses timing. The writer does not compensate by falsifying
timestamps. The probe records this discrepancy separately from numeric success.

See [complete report](qualification/native-edf-reader-20260915.json).
It is not evidence of native marker roundtrips, calibrated microvolts, arbitrary
EDF compliance, physical EPOC X interoperability or clinical readiness.

Reproduce using a **new** fixture directory and the isolated optional reader tools:

```sh
EEG_EDF_FIXTURE=/tmp/eeg-native-edf-new swift test --package-path apple --filter 'EDFNominalExportTests|EDFNominalPlanTests|EDFReceiptPlanTests'
/tmp/eeg-edf-readers-20260915/bin/python tools/qualify_native_edf.py /tmp/eeg-native-edf-new
./apple/build-native.sh all
```

Install reader tools in a separate venv from `requirements-edf-qualification.txt`
if the example environment is unavailable. They are not app runtime dependencies.
The probe asserts numeric/notice preservation and reports datetime qualification
separately; a successful process exit alone does not mean full timing qualification.

## Timestamp discrepancy localized

The follow-up probe now inspects **every** native EDF timekeeping record with
independent decimal arithmetic. All 263 record intervals across both files equal
exactly 1/128 second. First TAL onsets are `0.00999999` and `0.01781249` seconds.
A temporary fixture with only the second onset altered to `0.99999999` was rejected
by this interval check. Neither the native writer nor any library was patched.

The tagged [PyEDFlib v0.1.42 C header](https://github.com/holgern/pyedflib/blob/v0.1.42/pyedflib/_extensions/c/edflib.h)
specifies 100-nanosecond start-offset ticks (10,000,000 per second).
Its [Cython property](https://github.com/holgern/pyedflib/blob/v0.1.42/pyedflib/_extensions/_pyedflib.pyx)
returns the header value directly. The installed
[datetime helper](https://github.com/holgern/pyedflib/blob/v0.1.42/pyedflib/edfreader.py)
divides that value by 100 to obtain microseconds, whereas the documented units
require division by 10.

Observed raw offsets are 99999 and 178124 ticks: exactly the TAL values converted
to whole 100-nanosecond ticks. Converting those documented units to a separate
diagnostic datetime matches both fixture starts within one microsecond. This
localizes the observed discrepancy to the tested convenience conversion, rather
than evidence of incorrect EDF timekeeping. The original public helper results
remain in the report; they are not replaced by corrected results.

The report distinguishes `all_start_times_qualified: false` (public helpers) from
`all_low_level_starts_qualified: true` (edfio plus PyEDFlib raw ticks with explicit
unit conversion). The probe now asserts the latter in addition to sample checks.
This qualifies this synthetic subset and these reader paths only. Users relying
on the affected helper would still obtain incorrect fractional starts. Marker
translation, physical timing accuracy, hardware exchange and app export remain
unqualified; no app capability was enabled by this finding.

## Deterministic output-failure qualification

The writer now reuses the existing recording-output I/O boundary. Per-call test
wrappers surround real, exclusively created files; there is no mutable global
failure mode and no synthetic acquisition source in production.

Five native exporter tests pass. Injected failures cover a partial first-record
write, EDF synchronization, EDF close, a propagated cancellation error, and
receipt write/synchronization/close after both EDF segments are complete. All
seven ordinary failure paths remove their package and preserve source bytes.
The cancellation case injects `CancellationError` at the I/O boundary; it is not
a timed real-device cancellation trial.

Additional tests force cleanup failure: the first-record partial file remains
4,099 bytes, both errors and the package path are reported, and no completion
receipt exists. Receipt synchronization and close failure also leave no published
completion marker, even when cleanup fails and the pending JSON is parseable.
Existing-destination protection and deterministic successful exports remain tested.
This does not simulate every OS error, physical disk exhaustion, process crash,
permission race or filesystem implementation.

```sh
swift test --package-path apple --filter EDFNominalExportTests
```
