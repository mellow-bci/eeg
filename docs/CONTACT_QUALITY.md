# Contact quality: implemented extraction and unresolved classification

## Implemented raw path

`ContactQuality` is an offline tracker for revision 0740 and configuration
018000102010. It consumes decoded samples, retaining word 7 as raw CQ.

- Compute `slot = counter % 64` at the observed 128 Hz rate.
- Consume slots 0…13; other slots return no update.
- Assign slots in order: AF3, F7, F3, FC5, T7, P7, O1, O2, P8, T8, FC6, F4, F8, AF4.
- Clear remembered slot values on a counter discontinuity or nonconsecutive
  sample index; create a new tracker at each stream start.
- Return sample index, counter, slot, raw value, arrival time, observed slot count
  and electrode. Return `quality_level:null`; do not publish a green indicator.

The same-sample comparisons establish raw CQ agreement: 3,845/3,845 in the first
comparison and 15,361/15,361 in the later retest. They do **not** establish that
our classification matches Cortex because we do not yet produce classes.

## Static classification findings, not an enabled algorithm

The vendor code includes normalization `(value - offset)/divisor` and default
thresholds 0.2, 0.7, 1.3, 1.7. The traced constructor uses zero offsets with these
divisors:

| Electrode | Divisor | Electrode | Divisor |
|---|---:|---|---:|
| AF3 | 212 | O2 | 179 |
| F7 | 216 | P8 | 167 |
| F3 | 226 | T8 | 162 |
| FC5 | 235 | FC6 | 206 |
| T7 | 231 | F4 | 204 |
| P7 | 239 | F8 | 194 |
| O1 | 245 | AF4 | 179 |

Version/model branches and upstream transformations remain incompletely traced.
Do not apply those thresholds directly to the raw word merely because the output
would be in the right numeric range.

## Why classification remains open

TEST24 contained quality class 4 on every electrode and overall 100 throughout.
That cannot discriminate among candidate normalization algorithms. In the longer
reference table, CQ.AF3 changed 4 → 2 → 1 → 4 while nearby slot-zero raw values
remained about 5470. For example raw 5477 was associated with different subsequent
class values. A naive instantaneous threshold mapping is therefore unverified;
timing, state and upstream inputs need tracing.

The readout also distinguishes contact quality (`CQ`) from other vendor signal
quality fields (`SQ`). The screenshot showing good EEG quality does not prove
that every decoded sample is artifact-free biological EEG.

## Next qualification

Record controlled contact changes with synchronized direct and Cortex data,
trace update timing and normalization, and compare all class transitions. Only
then integrate class values into live readiness. Until then, downstream users
must see unknown contact quality, not an assumed good state.
