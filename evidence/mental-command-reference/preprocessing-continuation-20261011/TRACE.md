# Deployed stateful preprocessing filter

Reference is the installed arm64 CortexService SHA256 cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a. Captures are static LLDB disassembly/memory reads; no vendor code or trained assets are executed or bundled. A failed lookup for RealTimeFilter::apply appears in filter-init.txt: its actual virtual method is named filter, captured separately. The vtable memory read in filter-methods.txt used an incorrect address and is not evidence for dispatch; constructor/init/createAllFilters bodies supply that evidence.

## Construction / coefficient order

Cross-reference ../neutral-training-continuation-20261010/init-buffer-reset.txt: manager init 0x100b37c88..c9c copies three doubles from 0x102648090 into list sp+a8; 0x100b37cf8..d0c copies 0x1026480a8 into sp+90. Call 0x100b37d30..d3c passes first list x2=sp+a8, second x3=sp+90 and w1=2; stores filter at manager+b38. FilterTxf constructor 0x102133ae0 passes bool false to init, which sets order to equal-list-length minus one at 0x102133b8c..b90, stores first list at +28 and second at +40, and bool at +9c. createAllFilters 0x102133fa4/1340c8..1340fc therefore constructs RealTimeFilter (not NewRealTimeFilter) per row, with order two and lists unchanged.

Captured constants (IEEE doubles, decimal roundtrip):
- numerator b=[0.97554449992839098,−1.9510888162127069,0.97554449992839098]
- feedback a=[1,−1.9504906552523591,0.95168716081713]

No cutoff frequency, sample rate or filter designer is inferred from the constants alone.

## Arithmetic and initialization

RealTimeFilter::init 0x1021415c8 stores first coefficients +38, second +50, order +68, clears history lists +8/+20. filter 0x1021419b0..c28 loads these. If either history is empty it fills BOTH histories with the first input sample repeated order times (0x1021419f8..a18); unnamed helper 0x100b5c430 stores repeated d0 across a newly sized double list, including vector stores 0x100b5c500..524.

At 0x102141b3c..b68, b[k] multiplies x[n−k] in increasing k=0..2 with fused add; past samples come from history for negative indices. At 0x102141b80..bac, a[k] multiplies y[n−k] for increasing k=1..2 with fused subtract. Thus:

`y[n] = sum(k=0..2, b[k]*x[n−k]) − sum(k=1..2, a[k]*y[n−k])`

There is NO division by a[0]. Histories are chronological oldest→newest and update to last two samples/outputs, retaining earlier history if a block contains fewer than two samples (0x102141bbc..c08). FilterTxf::apply initializes/rebuilds all filters if row count changes (0x102134530..554); otherwise keeps state. It dispatches each contiguous Matrix row to the virtual filter with sample count and corresponding output row (0x102134658..688). Input/output shape is unchanged. This is Matrix row-major storage, separate from Armadillo fitting storage.

## Independent implementation and tests

ReferenceDeployedFilter implements only the proven finite order-two branch, with explicit maximumChannels and maximumSamplesPerBlock. Nonempty rectangular finite rows are required; overflow/nonfinite output rejects without publishing new state. These bounds/error/transaction choices are ours, not claimed vendor behavior. The vendor filter reads input[0] before checking count, so empty columns are deliberately unsupported. Empty row matrices and alternate NewRealTimeFilter are not emulated.

Tests cover nonzero first-sample history, ignored a0, analytic recurrence, independent rows, row-count reset, single-sample chunk equivalence, explicit limits and invalid/overflow atomicity. Five tests passed with `swift test --package-path apple --filter ReferenceDeployedFilterTests`. They are analytic reference-body tests, NOT matched Cortex runtime traces.

Remaining verification: matching numeric outputs from a Cortex reference session; caller timing and reset lifecycle across manager reinitialization; confirmation of upstream raw correction and classification windows in the complete deployed path. No complete live mental-command parity claim follows from this primitive.
