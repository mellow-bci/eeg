# Contact-quality validation work

## Implemented boundary

contact_quality.py is an offline research interpretation of existing decoded
samples. It does not change live acquisition, enable actions, or publish green
contact indicators. inspect_contact_quality.py preserves derived output in a
new exclusive-create JSONL file; original captures remain untouched.

Only revision 0740 plus configuration 018000102010 is accepted. The slot is
counter modulo 64, only slots 0..13 are consumed, and raw word 7 is retained.
A discontinuity clears remembered slots; each stream_start creates a fresh
tracker. No stale good-contact classification is carried across reconnects.
Electrode names now follow the static init-list trace. quality_level remains
null, with calibration/reference validation false. Earlier unlabeled outputs
are preserved; labeled replay is blinks-contact-quality-labeled.jsonl.

## Static evidence, installed official CortexService arm64

- headsetTypeFromVersion at 0x101fc9180 maps 0x07xx to type 7
  (0x101fc930c..0x101fc9318).
- isCqInRawData at 0x1010714a0 uses mask 0x14d; type 7 is a raw-data type.
- calculateCqChannelId at 0x101f25dc4 computes counter % (sample_rate/2),
  rejects indices outside channel count. Special type 2 decimation does not
  apply to type 7. At observed 128 Hz this gives modulo 64.
- init's branch table 0x102f6e650 routes type 7 to 0x101067810,
  setting channel count 14.
- getRawEegId table 0x102f6e900 routes type 7 to 0x101070d78;
  observed mode's mapping ends with CQ raw index 7 at offset 0x3c.
  init copies that field into this+0xa4; updateCQValues loads that raw slot.
- updateCQStates at 0x1010690bc computes (value - offset)/divisor, then
  compares against thresholds at this+0x230..0x248. Default constants from
  0x102f6e630 are 0.2, 0.7, 1.3, 1.7. Model/version-dependent handling exists.
- Constructor defines per-electrode normalization pairs. Complete mapping,
  upstream transformations, and reference agreement still require validation.

Saved disassembly: local-app-analysis/cq-routing.txt, cq-init-states.txt,
cq-constructor-raw.txt, cq-constants.txt, cq-threshold-values.txt.
No vendor process was attached to or modified; static disassembly only.

## Replay result

live-blinks-discovery-20260914T185827Z.jsonl produced 3,794 raw CQ updates,
271 for each of 14 slots. Saved as blinks-contact-quality-raw.jsonl.
This tests extraction coverage, not quality-level accuracy. All 19 software
regression tests passed, including unknown-config rejection and gap clearing.

## Independent reference plan

Official exportRecord can export raw EEG and per-sensor CQ together:
https://emotiv.gitbook.io/cortex-api/records/exportrecord

A genuine comparison needs an official export and acquisition provenance:
headset serial, firmware, configuration, exact recording interval, counters,
interpolation markers, processing/filter settings and units. Matching modulo
128 counters alone is insufficient because they wrap every second.

If Cortex and our collector cannot receive the same BLE samples concurrently,
sequential recordings can compare signal behavior but cannot establish
sample-for-sample decoder equality. Do not report correlations from unrelated
recordings as decoder validation. An identical-input reference or independently
calibrated signal source is required for that stronger claim.

Pending: confirmation that M4 EMOTIVPRO can record/export, complete calibration/upstream-transformation tracing, reference comparison, physical contact-change
validation, and integration into live quality status only after these checks.

## Reference import preparation

reference_csv.py validates the documented V2 CSV metadata, all 14 EEG/CQ
columns, finite values, increasing timestamps, counter ranges and CQ ranges.
It reports interpolated samples and counter discontinuities without dropping
them. SHA-256 identifies the imported artifact; decoder_validated remains
false. It cannot establish sample identity or compare unrelated sessions.

Format/error tests use explicitly synthetic CSV fixtures, not reference EEG.
M4 has EmotivPRO installed; launched via its official app path. No reference
export found in the targeted Documents/Emotiv or Downloads search (max depth
3); that limited search does not establish that no recording exists. Login
and export readiness remain unconfirmed.

Official CSV schema:
https://emotiv.gitbook.io/emotivpro-v3/managing-your-eeg-data-recordings/exporting-an-eeg-data-recording/csv-files
