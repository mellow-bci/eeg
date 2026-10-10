# Classifier JSON fields to numerical runtime

2026-10-11. Installed M4 arm64 CortexService SHA-256
`cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`.
Static bodies only; no vendor profile values, binary, model assets or storage salt
included. Previously captured bodies remain cited rather than copied again.

## Ten-field contract

Offsets refer to the Classifier, as established by the actual exporter in
`persistence-cache-continuation-20261011/classifier-json.txt` and inverse converter.

| JSON field | Storage | Numerical use and supported shape |
| --- | --- | --- |
| weightMeanVariances | +390, vector stride180 | Ordered class mixtures; weight is M×1, mean D×M, variances ordered D×D. M components, D=K−1. |
| classRefIDs | base ordered signed-int vector | Identity/provenance in this bridge; not a density coefficient. Caller label/decision mapping remains separate. |
| uniqueFeatureIndices | +20 unsigned vector | Select input feature rows, preserving index order/repetitions, before transpose into one feature row. |
| coeff | +d0 | PCA basis, selected-feature rows × PCA columns. |
| pcMeans | +180 | PCA center, one row of selected-feature width. |
| eigenvec | +230 | Canonical basis; retained-PCA rows, at least K−1 columns. |
| meanTot | +2e0 | Canonical center, one row of retained-PCA width. |
| numOfValidFeatures | +3a8 | Slice PCA output columns 0 through count−1 before canonical transform. |
| channelInUse | +3b0 | Retained metadata; not directly consumed by Classification::run math. Its broader noisy-channel/lifecycle use is outside this bridge. |
| useCount | +460 | Retained counter; not a density/projection coefficient. Broader cache lifecycle handled elsewhere. |

K comes from weightMeanVariances entry count in Classification::run at
1df5c..1df78; run requires K>1, otherwise empty output. Shape acceptance in JSON
alone does not prove any classifier can run. Our bridge explicitly rejects K<2,
misaligned identities, invalid feature ranges, incompatible matrices, zero/out-of-
range retained count, malformed mixtures and non-SPD covariance. This is a bounded
safe comparison contract, not a reproduction of vendor assertions/partial output.

## Selector and matrix orientation: fresh body evidence

`feature-selection.txt`: 1e918..91c stores uint16 0x100, then helper241a8.
`selector-helper.txt`: 24208..24240 selects row-index-vector branch for byte
flags0/1. `selector-column-tail.txt`: 24560..56c allocates selected-index count
rows and original column count; 24590..5c4 reads each index in original order,
checks against original rows, copies source(rowIndex,column) to result(indexSlot,
column). Despite the tail filename, this is **row selection**, not column
selection. Classifier run transposes selected features through helper2110c at
1e028..030 before PCA at1e044. Thus one original feature column becomes one
selected feature row, compatible with the existing vector kernel.

`transpose-materialization.txt`: helper2110c reads source rows/columns at21124,
allocates swapped dimensions at21128..30. General loop21254..2d4 reads source
column-major storage at offsets row+column*sourceRows and writes its transpose;
small-square branches preserve the same transpose. This resolves the previously
uncertain Matrix/Armadillo return bridge: fromArmadilloMatrix10212d080 transposes
via2110c, passes original rows/cols plus transposed raw buffer into the row-major
Matrix constructor at10212d10c..11c. Conversely toArmadilloMatrix10212cfc4 first
transposes the row-major Matrix, then creates column-major Armadillo with original
rows/cols. Logical(row,column) is preserved both ways. See earlier two-index
accessor equation columns*row+column in inverse-profile evidence.

## Mixture layout and transforms

`mean-matrix-bridge.txt`: probabilityCalculation at1f1fc..218 reads mixture weight
by linear component index. Existing complete `probability.txt` at1f0c0 reads
weight rows as component count; at1f108..138 constructs means subview(all D rows,
one component column) and calls23544. Fresh23544 at23570..58c loads source
subview rows/cols, allocates swapped dimensions;235d4..634 iterates underlying
column-major elements into transposed output. Thus means columns are components,
not rows; output is a row mean passed to Mvnpdf. Covariance vector indexing is
strideb0, in the same component loop. Runtime class WMV storage at1e3c8..3dc passes
weight base, mean+b0, variances+160.

Existing classification-run body at1e034..044 passes coeff/pcMeans to PCA;
1e0e8..11c slices leading numOfValidFeatures columns. 1e120..134 passes eigenvec/
meanTot and K to canonical transform. Existing transform bodies subtract center
and multiply basis. Canonical selects first K−1 basis columns. The bridge clips
PCA basis to the retained width before calling the same vector kernels, an
algebraically equivalent supported finite-domain operation. Its reported
pcaFeatures are the **retained** columns; the vendor stores full PCA diagnostic
state before slicing, which this bridge does not reproduce.

Class priors and neutralScale are Classification state, **not** any of these ten
JSON fields: prior pointer passed in run1e4e4 and scalar from self+b0 at1e4e8.
They remain explicit caller arguments. No default, sensitivity conversion,
threshold, command label, artifact decision or EEG front-end recipe is invented.

## Implementation and verification boundary

New ReferenceRuntimeProfile converts typed Codec.Classifier into existing
ReferenceGaussianPipeline.Parameters; selector slicing plus existing projection,
Gaussian mixture and posterior kernels form one math path. Typed signature packer
uses independent fitted values and the observed matrix layout. Explicit caller
numOfValidFeatures/useCount avoids claiming recovered broader builder/counter
policy; source class IDs are retained as independent provenance, not inferred
vendor final-ID update ordering.

Three analytic tests are provided for parent-coordinated execution:
1. Asymmetric two-component weight/mean column orientation and non-square PCA
   basis with leading-column truncation, explicit nonzero canonical center.
2. Shape/count/weight orientation/feature-index rejection independent of JSON
   schema flags.
3. Actual ReferenceClassifierRebuild.fit on independent two-class sufficient
   statistics, typed envelope→JSON→gzip→AES with a caller-generated key→inverse
   JSON→runtime; scoring invariance against pre-serialization and direct fitted
   existing kernels. No trained vendor profile or physiological data is involved.

Our <=70 bounds cover retained PCA width and Gaussian density dimension; raw
feature input and every stored matrix dimension are not universally capped at 70.
No builds were run by this subagent. Parent reported focused 235 executed,
233 passed, 2 skipped, 0 failed, including all three new tests; full core run pending.
This establishes
own-value serialization/scoring composition; it does **not** establish matching
trained Cortex outputs, accuracy of mental commands, exact Qt byte identity,
numerical eigenspace/sign identity, model portability on arbitrary/singular
profiles, batch runtime semantics, production qualification or exact full parity.
No vendor assets needed for this work. Exact trained-output parity still requires
a reference trained profile with matching feature vectors/output oracle.
