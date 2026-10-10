# Mental-command kernel parity — 2026-10-10

Current status: comparison-only arithmetic from windowing through Gaussian and
neutral scoring is implemented and unit-tested from static function bodies.
A private database snapshot is readable, but no trained profile has been found
in the checked M4 locations. **Full Cortex pipeline equivalence and hardware
qualification remain unverified.** Existing acquisition and runtime profiles are
unchanged. Historical milestones below are retained with dated updates.

Reference: installed M4 CortexService arm64, SHA-256
`cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`,
rechecked before this capture. Evidence and hashes are in
`evidence/mental-command-reference/kernel-trace-20261010/manifest.json`.
Only static LLDB target creation, disassembly and a five-byte dispatch-table read
were used. No vendor process was launched, attached, patched or bundled.

## Window: caller to arithmetic

1. Classifier constructor `0x100b1dd58–0x100b1dd68` constructs the window member
   at offset `0x380` with mode 1. The previously captured
   `hammingWindowTransform` calls that same member.
2. Window constructor `0x1021494f8` stores mode at offset 8.
3. `calculateCoeff` dispatch at `0x102149808–0x102149828` reads that mode. Table
   at `0x102ffe228` is `[00,7f,37,52,1d]`; mode 1 selects
   `0x10214982c + 4*0x7f = 0x102149a28`.
4. That branch computes, for i=0 through N−1:
   `h[i] = fma(cos((i * tau)/(N−1)), −0.46, 0.54)`.
   Constants are constructed in registers with bit patterns
   tau=`401921fb54442d18`, offset=`3fe147ae147ae148`,
   multiplier=`bfdd70a3d70a3d71`. Division and fused multiply-add order are
   retained in our implementation.
5. `apply(arma)` at `0x102149710` delegates coefficient multiplication to
   `0x102149b68`; its loop selects each column's coefficient and multiplies its
   rows. Our bounded public-to-module kernel accepts **one time series**, so it
   does not guess the upstream classifier's channel/time matrix construction.

Our policy: N<2, N>Int32.max and nonfinite samples reject explicitly. The
reference branch would divide by zero for N=1; we do not propagate that into
training. These input policies are our choices, not recovered vendor behavior.

## Scoring lowpass: state matters

1. Prior `scoring-lowpass.txt` plus `scoring-coefficients.txt` show first list
   `[0.2,0]` and second `[1,−0.8]` passed to `FilterTxf`.
2. Constructor `0x102133ae0–0x102133ae4` passes false to `init`; the factory
   branch `0x102133fa4–0x1021340fc` therefore selects **RealTimeFilter**, not
   NewRealTimeFilter. The coefficient lists are preserved by `init`.
3. `RealTimeFilter::init` stores the first list at offset `0x38` and second at
   `0x50`. `filter` uses the former for feedforward FMADD accumulation and the
   latter (starting at element 1) for feedback FMSUB accumulation.
4. `filter` at `0x1021419e8–0x102141a20` initializes missing histories to the
   **first input**, via helper `0x100b5c430`. That helper fills the requested
   history length with its incoming scalar (vector and scalar store loops).
5. The order-1 recurrence is `y[n]=0.2*x[n]+0*x[n−1]+0.8*y[n−1]`, with both
   initial histories set to x[0]. Arithmetic retains the feedforward then
   feedback fused accumulation. Last input/output persist across blocks.

This is a scalar kernel. Per-class filter allocation, scoring-manager reset
triggers, thresholds and interpretation of its inputs remain untraced. Empty
blocks are no-ops and nonfinite blocks reject without state changes in our API;
these are explicit independent safety policies. No command is emitted by it.

## Implementation and verification

`apple/Sources/EEGCore/ReferenceMentalKernels.swift` contains both internal
kernels. They are intentionally not selectable by existing production profiles:
changing the feature window without retraining invalidates learned parameters.
They are building blocks for the same EEGCore processing path once the complete
reference recipe is understood, not a second acquisition pipeline.

Run:

```sh
swift test --package-path apple --filter ReferenceMentalKernelsTests
```

Tests cover analytic Hamming landmarks and symmetry, time-series multiplication,
unsupported lengths/nonfinite values, nonzero startup history, step/impulse
responses, exact block partition invariance and reset/rejection state handling.
These tests verify implemented mathematics and state contracts; they do **not**
compare execution against a running vendor classifier. No physiological
accuracy or mental-command parity follows from their success.

## Ordered remaining work

| Order | Missing evidence/implementation | Acceptance gate |
|---|---|---|
| 1 | Trace preprocessing and FFT_Txf mode 2, normalization, complex post-transform helper `0x100b22cdc`, and Complex2Real mode 0. | Explicit axis, DC removal, length, bin, scale and transform contract; analytic and independent numerical fixtures. |
| 2 | Trace feature selection and PCA/canonical training transforms, matrix layout and fitted parameters. | Session-separated fitting; orientation/centering fixtures and versioned recipe; no guessed dimensions. |
| 3 | Resolve weighted Gaussian probability and posterior's two upstream helper calls. | Class order, priors, repeated components, scalar meaning, normalization and edge cases evidenced and tested. |
| 4 | Trace neutral training/acceptance, sensitivity mapping and scoring-manager filter lifecycle. | Reproducible training and reject/neutral behavior; parameter provenance; reference comparisons where outputs available. |
| 5 | Integrate the completed recipe into canonical training/replay/inference with new versioned profiles. | Existing decoder/replay regressions pass; no reuse of incompatible profiles; explicit unsupported states. |
| 6 | Obtain fresh labeled held-out sessions and ordinary-activity negative controls. | Precision/recall, false activations, latency, cross-session robustness and artifact confounding reported; hardware gate remains closed until measured. |

If a learned asset, encrypted model or calibration table becomes necessary,
record its call site and role and notify the user before copying or using it.
No asset dependency has been established for the window and lowpass above.

## Extended milestone — FFT through neutral scoring (2026-10-10)

Added internal, explicit-parameter implementations without changing acquisition or existing profile inference:

| Stage | Implemented evidence-backed behavior | Remaining verification gate |
|---|---|---|
| Spectral | Normalized half-spectrum squared magnitude, DC included/Nyquist excluded; inclusive ceil band endpoints; twice band mean | Real Cortex intermediate outputs, full raw preprocessing and recipe |
| Learned transforms | Centered PCA and canonical projection, canonical K−1 truncation | Matching learned matrices, feature ordering and trained profile |
| Gaussian | Full covariance Cholesky, weighted component densities and self-peaks | Matched parameters and Cortex outputs; floating tolerance |
| Posterior | Prior-weighted class likelihoods, appended min(peak)*scalar, normalization | Actual caller scalar and class ordering |
| Neutral/command | Two neutral slots; activation-setting mapping, top-two margin, 0.3 latch | Headset sensitivity configuration, LPF matrix cadence, lifecycle |

Sources: `spectral-followup-20261010/TRACE.md`, `gaussian-followup-20261010/TRACE.md`, `neutral-followup-20261010/README.md` under `evidence/mental-command-reference`.

`ReferencePipelineCompositionTests` passes a synthetic spectral feature through transforms, mixture scoring, posterior, per-slot lowpass and command/neutral handling. Parameters and update cadence are explicitly our test fixture, NOT recovered vendor defaults. It checks command activation, return to trained neutral and appended-neutral rejection. It does not prove physiological decoding or full Cortex parity.

Reproduce: `swift test --package-path apple --filter 'Reference|DecoderTests'`.

Next gates in order: close preprocessing axes and channel-band/ratio mapping; establish full profile recipe and LPF cadence; compare intermediate outputs using identical input and parameters; trace training/neutral autosampling and persist versioned independently trained profiles; evaluate held-out recordings and cross-session false activations. Do not substitute the existing independent classifier's parameters.

### Asset decision

No vendor trained assets have been copied or incorporated. Exact comparison with a particular trained Cortex profile needs its PCA/canonical means and bases, Gaussian component means/covariances/weights, priors, class order, selected features and relevant sensitivity configuration, plus reference outputs. The user authorized local inspection for comparison. M4 read access is now verified after the user granted an ACL. The database rejects a plain read-only SQLite open. The corrected fixed-key and page-codec reference probe now produces a readable private snapshot; quick_check passes, while full index integrity needs the application-specific fl_value function. The separate training-attributes store is empty; no trained profile has been obtained. See `profile-followup-20261010/TRACE.md` for the loader and JSON field evidence. Authorization to inspect is separate from permission to distribute anything. Independent training can create our own parameters but alone cannot establish equality to a vendor profile.


## Composed comparison path and external evidence gate

`ReferenceMentalPipeline` is an internal comparison composition, not a new
acquisition or enabled inference recipe. Its inputs are explicitly preprocessed
windows. Selected band powers are converted to **10*log10(power)** based on
`BandRatioTxf::returnBandPowerOnly` function-body evidence. Dimensions, ordered
feature coordinates, class order, learned transforms, Gaussian parameters,
priors, neutral scalar and activation setting must all be supplied. Nothing
silently falls back to our independent v2 classifier. Failures do not consume
filter/activation state. Profile changes and packet gaps require explicit reset.

The optional external test checks every stage and exact emitted action, with
bounded absolute/relative numerical tolerances. Missing fixture is **skipped**,
never verified parity. The current M4 binary identity is pinned; profile and
source-output hashes are declared metadata and must be independently audited
against their source files. The harness does not authenticate arbitrary JSON.
A whole-pipeline output match without intermediate vectors is a different,
narrower experiment and must not be substituted here.

Reproduce our implementation checks:

```sh
swift test --package-path apple --filter 'Reference|DecoderTests'
```

For an actual comparison, store a normalized external fixture outside the repo:

```sh
EEG_CORTEX_COMPARISON_FIXTURE=/absolute/private/path/comparison.json \
  swift test --package-path apple --filter ReferenceMentalPipelineTests.testExternalCortexStageComparison
```

The fixture schema is defined by `Fixture` and `ExpectedFrame` in
`ReferenceMentalPipelineTests.swift`. Required top fields: version=1,
origin=cortex-observed-stage-outputs, referenceBinarySHA256,
referenceProfileSHA256, referenceOutputsSHA256, absoluteTolerance,
relativeTolerance, recipe, and a nonempty frames array. The normalized recipe
is Codable `ReferenceMentalPipeline.Recipe`, deliberately **not** a direct
vendor profile deserializer. Each frame includes explicit resetBefore,
preprocessedSeries and the observed spectra, bandPowers, features, pcaFeatures,
canonicalFeatures, classDensity, classPeakDensity, posterior, filteredPosterior,
action and power. Unobserved values must not be manufactured with our own code.

Remaining gates, in order:

1. Establish actual window size/hop, channel order, feature coordinate values,
   deployed feature mode, sensitivity configuration and LPF reset/cadence.
2. Finish fitting/acceptance/neutral autosampling bodies; record algorithm and
   parameter evidence before implementing the training recipe.
3. Obtain a trained profile plus recorded Cortex intermediate outputs. The M4
   attribute store is currently empty. The user chose offline work rather than
   a fresh training trial. An existing profile elsewhere or a future labeled
   neutral + one-action training session is needed for this comparison.
4. Run the external stage comparison with a reviewed reference capture protocol.
5. Integrate an independently fitted, versioned recipe only after these gates;
   run held-out session and ordinary-activity negative-control experiments.

No vendor binaries, embedded secrets, decrypted database, trained parameters,
account records or model assets are included in tracked deliverables.

## Training continuation (2026-10-10)

The current bounded reference implementation covers these additional bodies:

| Stage | Implemented subset | Explicit gap |
| --- | --- | --- |
| Training statistics | Feature-row/epoch-column means, unbiased covariance, counts and coordinate scatter | Singleton epoch/vector reinterpretation and upstream acceptance recipe |
| Pooling | Per-feature count masks, weighted means, pair-count covariance and timestamp arithmetic | Empty shared selection and nonvector count domain |
| Feature ranking | Inclusive 20-epoch eligibility, asymmetric standardized mean separation, worst competitor, count-derived budget and selected union | A tied score across the truncation boundary rejects; vendor unstable tie permutation unverified |
| PCA | Explicit covariance eigenbasis and body-derived cumulative-99-percent dimension policy | Full class/epoch extraction recipe and singular covariance domain |
| Canonical fitting | Nonsingular within/between scatter whitening, eigenbasis and pooled within-variance normalization | Singular retry branch and full training orchestration and singular-domain behavior |
| Bartlett diagnostics | Reverse reciprocal cumulative products, statistic multiplier and degrees of freedom | No significance or rank decision proven in the captured function; downstream consumer remains to trace |
| Epoch counts | Thresholded Cartesian extraction with repeated indices and first-column-mean projection | Overflow/empty-domain vendor error behavior |
| Neutral training | Paired Matrix-epoch buffering, configured minimum, control stop, lock/unlock/reset and differentiated completion outcomes | Upstream validity derivation, actual builder/save implementation and acceptance policy |
| Composition | Analytic two-class feature epochs → fitted statistics → pooling → PCA → canonical fit → full Gaussian inference → command/neutral decision | Not a recorded Cortex profile or a raw-recording-to-trained-profile recipe |

Sources and support policies are recorded in the pooling, feature-selection,
canonical, training-statistics, epoch-count, Bartlett and neutral-training continuation TRACE files under
`evidence/mental-command-reference`. LAPACK/sign conventions, finite/SPD
validation, maximum buffer capacity and numerical dimension bounds are our
explicit policies. None are presented as recovered vendor defaults.

The existing independently designed live trainer and acquisition are preserved.
These primitives remain internal reference code: no UI or runtime substitution
is made before recipe and reference comparison gates pass. A completion event
from autosampling is not a successful fit; insufficient data and build/save
failures have distinct outputs.

No vendor asset is needed for the implemented arithmetic. Exact comparison
still needs a participant-trained profile's selected coordinates, learned
PCA/canonical matrices, Gaussian statistics, priors/settings and corresponding
Cortex-observed stage outputs. The checked M4 store was empty; the optional
external comparison remains skipped. Synthetic analytical tests do not establish
physiological command accuracy, exact parity or production qualification.

Validation checkpoint: final focused Reference/Decoder run executed 74 tests,
with 72 passed, two explicit skips and zero failures. The broader EEGCore run
executed 251 tests, with 247 passed, four explicit skips and zero failures;
it preceded the final statistics/Bartlett additions and final composition
update, which are covered by the subsequent focused run. The skipped matched
Cortex comparison remains unavailable, not passed. Static reference binary
SHA256 was rechecked on M4 and matches the pinned identity.

Next offline order is to trace full training orchestration and acceptance,
rebuild/mixture-weight policies, deployed front-end recipe and downstream Stats
consumers. Unsupported edge domains (singular fit, singleton statistics,
empty shared pooling and tied selection cutoff) must gain explicit evidence or
remain rejected. Then obtain local trained reference parameters and observed
stage outputs for the existing comparison harness; prospective held-out
physiological evaluation is a separate gate after numerical comparison.

## Training acceptance and orchestration continuation (2026-10-11)

| Area | Newly implemented comparison subset | Remaining boundary |
| --- | --- | --- |
| Collection | Actual six-byte control jump table; sample/whole-second wall timing, strict start delay, validity gate, rolling paired buffers, one-shot events | Caller-supplied MatrixStream step and upstream validity, real raw-feature recipe |
| Acceptance | Minimum epoch gate, separate event versus fit/save outcome, build/clear/save/update/unlock ordering, rejection and reset state | Actual cache, brain-map, count mutations and complete classifier builder remain required operations |
| Training bank | First matching class appends a separate Gaussian; explicit features/first timestamp, no replacement | Feature construction and metadata from deployed front end |
| Class weights | Neutral1, action exponential or explicit ten-entry table; no guessed table values | Table loading/initialization and consuming normalization |
| Signature orchestration | Ordered class folding → feature selection → selected means/counts/covariance → metadata channel set → explicit fitted artifacts → unit-component weights | Complete PCA/canonical scatter construction remains explicit required fitting input, not fabricated |
| Edge domains | Scalar singleton covariance, PSD PCA zero eigenvalues/allzero empty rank, bounded canonical diagonal repair with provenance, empty-shared pooled diagnostic state | Tied ranking cutoff and unsupported singleton/vector shape remain rejected; bounded policies are our choices |

Evidence: `training-lifecycle-continuation-20261011`,
`training-bank-continuation-20261011`, `signature-continuation-20261011`,
`training-edge-continuation-20261011`, each under
`evidence/mental-command-reference`, contains actual static bodies and TRACE.
The acceptance callback test takes20 analytic Matrix epochs through the lifecycle
into actual training-bank mean/covariance/count fitting. It explicitly reports
save failure because no classifier persistence occurs. Callback interfaces mark
unrecovered algorithms; they are not completed Cortex parity implementations.

The binary accepts training with event4 even on builder/save failure. Our result
separates those outcomes, and tests check operation order. Insufficient accept
leaves active/timer unchanged in the traced body; comparison code preserves that
behavior. Separate resetState is necessary before a new attempt. No vendor asset
was needed for these arithmetic/state additions. Participant-trained profile and
matched stage outputs remain missing private comparison inputs. No change to
acquisition, independent live trainer, UI or Cast was made by this work.

Remaining offline work is the deployed front-end feature/window/validity recipe,
full fitting scatter/center construction, cache/rebuild and profile count/brain-map
mutations, weight-table initialization/consumer, ranking ties and downstream Stats
consumers. Exact observed numerical comparison and prospective session-separated
physiological evaluation still remain separate gates. This checkpoint does not
claim that all offline work, full Cortex parity or production qualification is done.

Further Oct11 body tracing reduces the fitting boundary: `ReferencePCAFitting`
folds selected single-class Gaussians in order, eigendecomposes pooled covariance
and uses pooled mean as PCA center, with the recovered rank policy. Low-epoch
clipping and singular spectra reject in this composed normal-support path;
separate edge kernels do not establish the complete singular recipe.
`ReferenceCanonicalScatter` projects each class first, then pools projected
Gaussians and constructs T=(N−1)Cpooled, E=sum((ni−1)Ci), H=T−E, df=N−K.
This order matters with heterogeneous counts. The pooled mean is retained as
provenance; its role as a runtime canonical center remains unverified.
`ReferenceTrainingProfileUpdates` increments/reconstructs training counts using
an explicit supplied action-column catalogue, and retains surviving trained-action
ordering before appending newly present actions. Database existence flags are
inputs, not inferred success. Per-normalized-headset sensitivity-table loading is
traced; configuration source and actual table values remain unresolved.

Final focused checkpoint:115 executed,113 passed,2 skipped,0 failures.
Broader EEGCore checkpoint:294 executed,290 passed,4 skipped,0 failures; it
preceded final epoch assembly/persistence refinements and PCA/scatter/profile
additions, all covered by the final focused run. No skipped Cortex fixture is
counted as passing. Commands: `swift test --package-path apple --filter EEGCoreTests`
and `swift test --package-path apple --filter 'Reference|Decoder'`.
