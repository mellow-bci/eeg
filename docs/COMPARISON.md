# Identical-sample reference comparison

Implementation: [compare_paired.py](../compare_paired.py).

## Algorithm

1. Require a nonempty direct capture with a final summary and calibrated electrode values.
2. Read only EEG electrode values, counter, interpolation flag, Timestamp and optional raw CQ from the recovered Parquet reference.
3. Exclude reference rows with non-finite electrode/counter/time values or `EEG.Interpolated != 0`.
4. Convert reference voltage back to ADC-grid integers with `round(voltage * 7.8)`. Report the maximum grid residual rather than claiming floating-point identity.
5. Index reference rows by `(counter, AF3, F7, F3, FC5, T7, P7, O1, O2, P8, T8, FC6, F4, F8, AF4)` in ADC units.
6. Require exactly one reference candidate for a direct sample. Zero candidates = unmatched. Multiple candidates = ambiguous/unverified.
7. For matched rows, measure absolute voltage differences across all 14 channels and compare raw CQ independently.
8. Evaluate every transport-stable sample. Reference row indices must be contiguous within each `(epoch, stable_segment)`. Empty stable sets do not pass.
9. Retain unmatched/ambiguous indices, order reversals, direct summary, source identity and SHA-256 hashes.

The previous one-off comparator also reported a suffix starting at hardcoded index 31. That observation remains in the historical report; the maintained comparator has no such cutoff and uses recorded stability/segment boundaries.

## Reproduce the latest comparison

```sh
.venv/bin/python -m pip install -r requirements-analysis.txt -r requirements-reference.txt
.venv/bin/python compare_paired.py archive/current-state/epoc-cortex-retest-20260915-01.jsonl archive/current-state/reference-retest/recovered.parquet --output recordings/recomparison.json
```

Keep the headset/configuration and same-acquisition provenance alongside the report. Full vector matching is much stronger than counter-only matching, but it is still an empirical reference comparison. The comparator does not independently authenticate the physical source, certify biological EEG, prove all firmware variants, or validate different contact-quality classes. Header/counter checks cannot replace a BLE message authentication code.
