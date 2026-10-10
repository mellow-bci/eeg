# MatrixStream epoch assembly

CortexService arm64 reference SHA-256:
`cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`.
Function bodies were statically disassembled; no vendor assets required.

## State and exact normal-domain behavior

Constructor `0x10213ee04` stores sample rate at offset0, cursor at offset`0x18`
and matrix buffer pointer at offset`0x20`. At `13ee0c..13ee1c`, duration `d0`
and step duration `d1` are multiplied by signed integer sample rate, converted
by `FCVTZU`, and stored as window samples at `0x8` and step samples at `0x10`.
Thus finite positive products truncate toward zero. `stepSizeInSample`
(`13ee24`) reads the latter, without a further conversion.

The existing initialization caller (`init-buffer-reset.txt`,
`0x100b38468..3849c`) supplies its existing buffer, configured durations,
sample rate and initial cursor zero, then calls reset. Profile defaults are
not invented by this primitive.

`next` (`0x10213eedc`) checks buffer nonempty and `cursor+window <= columns`
(`13eef4..13ef14`). Otherwise it returns an empty matrix without advancing
cursor. A successful call copies all rows, columns `[cursor,cursor+window-1]`
(`13ef2c..13ef58`) and then advances cursor by step (`13ef5c..13ef64`).
There is no loop to drain the buffer and no implied scheduling guarantee.

`nextWithRemoval` calls next exactly once (`13ef98`). An empty result returns
without changing buffer or cursor (`13efa0..13efa4`). A nonempty result clears
the matrix if buffer columns equal step (`13efa8..13f004`); otherwise it keeps
all rows and columns `[advanced cursor,last column]` via in-place subset
(`13f03c..13f068`). It then resets cursor to zero (`13f06c`). If next() calls
previously advanced the cursor, removal includes that consumed prefix too.
It is not always a fixed one-step removal.

`reset` replaces the pointed buffer with an empty Matrix (`13ee40..13ee90`)
and zeros cursor (`13eebc`). `operator<<` ignores empty input, copies input
when buffer is empty, otherwise concatenates by column with Part2
(`13f178..13f1ec`). The `concatByCol` Part2 branch (`1388ec..138a04`)
copies each existing row first (`138988..138998`), then the incoming row at
the existing column offset (`13899c..138a04`), proving append order. It does
not reset the cursor.

## Independent support boundary

`ReferenceEpochStream` implements those behaviors with channel rows and sample
columns. It requires positive finite timing products of at least one sample,
step <= window, rate and buffer capacity within Int32 positive range, finite
rectangular matrices and at most70 channels. The buffer capacity is explicitly
supplied by the caller; there is no hidden window-count limit. Validation fails
before mutation. These limits are our policies, not recovered Cortex values.

Zero step/window, exceptional floating conversion, step larger than window,
external mutation of the vendor shared buffer, channel shape errors and
unsigned overflow are outside the supported comparison domain. No repair,
interpolation, dropping of samples or automatic backlog draining is substituted.
The live acquisition path remains unchanged.

Five analytic tests cover overlapping windows, exact equality completion,
single-result calls, persistent cursor and subsequent prefix removal, reset,
append, sample-count truncation and transactionally rejected malformed input.
The focused suite passed five tests with zero failures.

Reproduce:

```sh
ssh -o BatchMode=yes m4 'lldb -b -o "target create --arch arm64 \"/Applications/EmotivApps/EMOTIV Launcher.app/Contents/MacOS/CortexService\"" -o "disassemble -s 0x10213ee04 -e 0x10213eedc" -o "disassemble -n Cortex::Math::MatrixStream::next" -o "disassemble -n Cortex::Math::MatrixStream::nextWithRemoval" -o "disassemble -s 0x10213f15c -e 0x10213f208" -o quit'
cd apple
swift test --filter ReferenceEpochStreamTests
```
