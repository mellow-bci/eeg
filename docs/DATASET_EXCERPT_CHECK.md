# Native dataset excerpt-reuse check

`canonical-counter-adc-blocks-v1` is an independent validation rule, not a recovered
Cortex algorithm. `EEGTrainingDataset.load` applies it before returning a dataset
for native training or evaluation. Existing whole-recording hashes remain intact.
A match rejects the dataset visibly as `reusedRecordingExcerpt`; it never changes
raw samples, trial labels, a profile or inference output.

## What is compared

Each sample is encoded as a little-endian UInt16 counter followed by the 14
canonical-order integral UInt16 ADC values (30 bytes). Missing, nonfinite,
nonintegral or out-of-range values are rejected. Timestamps, filenames, index,
metadata and derived microvolts are excluded deliberately. All samples delivered
by the recording store's analysis traversal are inspected, including rejected
windows and the final partial window, not only accepted labeled feature windows.

For each earlier manifest session, retain its nonoverlapping 256-sample blocks.
For the next session, inspect a rolling 256-sample block at **every sample offset**.
A UInt64 polynomial hash (base 257, wrapping arithmetic) locates candidate blocks;
full canonical byte equality must confirm the match. Hash collisions alone cannot
reject data. Commit that session's sparse blocks only after its other validation
passes. Blocks repeated within a single session are not treated as cross-session
reuse. All manifest splits are checked, including train/train and eval/eval.

An identical consecutive excerpt of at least 511 samples necessarily contains a
whole earlier indexed block, regardless of excerpt alignment, provided the
canonical samples are present unchanged in the traversal. Shorter excerpts may be
detected if they contain an indexed block. No detection is promised below that
boundary. At 128 Hz, these are 256/128 = 2-second blocks and 511/128 sample-count
seconds (about 3.99 seconds); this is not a wall-clock continuity claim.

## Limits and resources

- This detects identical raw content, not how it arose. Flat, saturated or synthetic
  repeated sequences can also match; they are unsuitable evidence of independent
  sessions until investigated. The app does not accuse the operator of copying.
- Altered counters, resampling, filtering, changed channel values and shorter
  excerpts can evade this check. Passing is not proof of acquisition independence.
- Only sessions in the loaded manifest are compared. A saved profile retains whole
  source hashes, not this raw block index; evaluation without its historical
  training sources cannot exclude historical partial reuse. Parent lineage and
  historical tuning/evaluation reuse remain separate unverified concerns.
- Raw block payload storage is at most 30 bytes per indexed source sample, plus
  dictionary/set overhead. The rolling buffer is 7,680 bytes per current session.
  Duplicate blocks share set entries. The caller's existing dataset resource limits
  do not impose a byte limit on this index; large datasets require sufficient RAM.
  No silent truncation, subscription cap or sampling of the check is used.
- Cancellation is checked by the dataset loader at each analysis-window boundary.
  This change neither connects hardware nor modifies the recorder/decoder.

`native-labeled-evaluation-6` receipts describe the check and historical-source
limitation. Version 5 receipts predate it; they must not be described as checked by
this rule. Python research loading has not adopted this native rule and is not an
alternate production route.

## Reproduction

```sh
swift test --package-path apple --filter 'RecordingOverlapTests|TrainingDatasetTests|LabeledEvaluationTests'
```

Tests use synthetic ADC sequences, not wearer data: a clock-shifted unaligned
excerpt, exact block reuse, changed content, explicitly undetected short content,
and native dataset rejection for differently sized recordings sharing samples.
The existing full recording-to-training-to-held-out-evaluation test must continue
to pass with distinct source content. These checks establish software behavior;
physiological qualification remains outstanding.

Validation checkpoint (2026-09-15): 13 selected native tests passed, including the
recording-to-profile-to-held-out-evaluation route. A subsequent four-test overlap
suite also passed, adding every one of the 256 possible excerpt-start alignments
at the 511-sample boundary. That alignment test processed 130,816 synthetic input
samples in 2.017 seconds in the debug test process; this is not a hardware/UI
latency or memory benchmark. All three native platform builds succeeded. No live
headset experiment or app interaction was performed for this validation rule.
