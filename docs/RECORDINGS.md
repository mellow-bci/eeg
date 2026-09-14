# Standalone recording access

`recordings.py` provides read-only inventory, description, replay and CSV export for
our existing pipeline JSONL. It has no Emotiv account dependency, deletion operation,
cloud upload, entitlement, or quota. Disk capacity and explicit acquisition limits
still apply; this module does not change capture limits or the device sampling rate.

## API

```python
from recordings import RecordingLibrary
library = RecordingLibrary('/absolute/path/to/recordings')
items = library.inventory()
metadata = library.describe('session.jsonl')
page = library.replay('session.jsonl', offset=0, limit=500, stride=1,
                      channels=['AF3', 'AF4'], units='adc', stable_only=False)
# Caller opens an exclusive/private temporary output and publishes only on success.
with open('/private/output.tmp', 'x', newline='') as output:
    result = library.export_csv('session.jsonl', output,
                                channels=['AF3', 'AF4'], units='microvolts')
```

The application must create export files with mode 0600, remove an incomplete export
on exception, and only expose the final download after success. `export_csv` writes
one row at a time to the supplied text stream. It does not buffer the entire recording.

## Completion and correctness

- `complete` requires a stream-start event and a final summary event, with no malformed
  lines. A closed capture can be complete while `capture_clean` is false.
- A missing final summary or partial trailing line is `incomplete`: this may be an
  active recording, interrupted writer, or crash. This format alone cannot distinguish
  those cases; combine it with the application's active capture state.
- Invalid JSON, missing event kind, or non-finite JSON constants mark a file `corrupt`.
- Description reports observed EEG/stable/calibrated counts and event counts alongside
  the original summary. Summary counters are not substituted for observed counters.
- Replay/export reject malformed events and missing requested electrode/units fields.
  Microvolts never silently falls back to ADC. Microvolt values remain uncentered.
- Transport stability does not assert good electrode contact or validated physiology.

## Replay semantics

`offset` counts eligible samples after optional stable-only filtering. `stride` selects
one out of every N samples beginning at that offset; `next_offset` is the next selected
sample's index in that filtered sequence, or null at the current file boundary. Return
metadata includes electrode names, units, stability, epoch, stable segment, counter,
arrival time and continuity. Never interpolate lines across epoch/segment boundaries.

This downsampling is **point selection for preview**, not an anti-alias filter or a
scientific resampling algorithm. Every source sample remains available at stride 1.
There is a maximum 10,000 returned samples per page and 4 MiB per JSONL line. Each read
freezes its initial file byte boundary so concurrent append cannot make it run forever.
Pagination currently scans from the beginning (bounded memory, linear read time);
large archives may require a separately validated persistent index before interactive
performance is guaranteed.

## Filesystem and data handling

Only plain ASCII basenames ending `.jsonl` are accepted. Paths, traversal and symlink
recordings are rejected. Opened descriptors must be regular files. The caller supplies
the trusted recording directory; the library does not accept a directory from a web
request. Inventory omits symlinks and non-files. JSON lines and EEG numeric metadata
are validated before export; arbitrary text cannot become spreadsheet formulas.

All files are private physiological data. The library never sends them anywhere.
The app must provide its own authenticated/local-only access boundary and avoid logging
sample contents. There is no deletion endpoint.

## Validation

Six tests cover complete versus incomplete/corrupt records, path traversal/symlink
rejection, stable filtering and pagination, absent calibrated data, CSV formula input,
and the real paired fixture. Its stable microvolt export contains **15,108** samples;
the recording description sees **15,374** total samples and values match replay.

```sh
python -m unittest discover -s tests -p test_recordings.py -v
```
