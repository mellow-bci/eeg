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
and uses pooled mean as PCA center, with the recovered rank policy. At that checkpoint low-epoch
clipping and singular spectra rejected in the composed normal-support path;
separate edge kernels do not establish the complete singular recipe.
`ReferenceCanonicalScatter` projects each class first, then pools projected
Gaussians and constructs T=(N−1)Cpooled, E=sum((ni−1)Ci), H=T−E, df=N−K.
This order matters with heterogeneous counts. The pooled mean is retained as
provenance; its role as a runtime canonical center was unverified at that checkpoint (resolved below).
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


## Deployed recipe, low-epoch PCA, runtime centers and cache — 2026-10-11

| Area | Body-supported implementation in this checkpoint | Explicit remaining boundary |
|---|---|---|
| Deployed input filter | Order-two RealTimeFilter recurrence with captured b/a lists, first-sample seeded x/y history, row-count reset and chunk continuity. | Finite nonempty bounded support; alternate filter implementations and full raw correction/reset lifecycle still separate. |
| Deployed feature recipe | Ordered power and ratio metadata coordinates; both wrappers use mode1: 10 log10(P) or 10 log10(Pnum/Pden); computation gate includes training with no classifier. Existing comparison pipeline reuses the extraction kernel. | Actual deployed coordinates/bands/settings must be supplied. Preprocessing and noise-derived detection validity remain separate from contact quality. |
| Contact gate and training background | Default headset branch overallCQ>=50; optional training background subtraction initializes on first clean feature and saturates counter480 into (479*mean+x)/480. Both training and detection consume the processed clean features (corrected after tracing the stack arguments). | Input CQ remains vendor numeric data; this is not raw quality decoder validation. Special untested headsets not enabled. |
| Epoch stream | Positive finite rate-duration products truncate; append columns; one window per next call; nextWithRemoval removes advanced cursor prefix; reset clears buffer. | Explicit caller capacity and step<=window are independent support boundaries. No guessed profile cadence. |
| Low-epoch PCA | If every feature count<=p, clips descending eigenpairs using first feature scratch count min(n[0]-1,p), then inclusive endpoint trunc(scratch[0]-1). Wired before rank selection in ReferencePCAFitting. | Counts>=2 finite support only. Shared PSD eigensolver now retains zero roots; singular downstream Gaussian scoring and exceptional conversion semantics remain explicit gates. |
| Runtime centers | Original pooled mean is PCA center; canonical runtime center is zero on traced builder path. Final class mean=(projected class mean-pooled projected mean)*B; covariance=B'CB. | Heterogeneous-count training/runtime center differences are exposed, not corrected. LAPACK basis/sign policy remains independently chosen. |
| Classifier cache | Ordered comma keys; exact action-vector insertion check; disable and size changes clear entries; minimum reuse-count eviction with lexical ties; manager reuse increment wrapsUInt64; dirty action removal. | Database cache serialization and full manager persistence integration remain documented boundaries. Zero vendor maximum is uncapped; our explicit storageLimit is a safety policy. |

Evidence: `deployed-feature-continuation-20261011`, `low-epoch-continuation-20261011`,
`runtime-centering-continuation-20261011`, `cache-continuation-20261011` and
`stream-continuation-20261011` and `preprocessing-continuation-20261011`, each with captured bodies, address-level explanation
and pinned hash manifest. ReferenceFittedWorkflowTests composes pooled fit→PCA→
canonical scatter/fit→runtime centers→Gaussian inference using analytic inputs;
it is not an observed Cortex comparison or participant experiment.

No vendor learned asset was needed for these primitives. Completing comparison
with a particular deployed Cortex classifier still requires its actual feature
configuration, trained transforms/Gaussians and matched reference outputs. The
checked training store was empty. Remaining offline questions include final singular class-density behavior, complete
fitted-artifact/persistence orchestration and actual deployed parameter values.
The next checkpoint below resolves bounded sensitivity and error-set routing contracts. Hardware and physiological
validation remain separate. Full Cortex parity and production readiness are not
claimed; optional unavailable Cortex fixtures are skipped, never counted passing.


Checkpoint reproduction: `swift test --package-path apple --filter 'Reference|Decoder'`
executed143 tests:141 passed,2 explicitly skipped,0 failures. Evidence integrity
checks and `python3 tools/render_capability_matrix.py --check` passed. The
optional matched Cortex fixtures remain absent; analytic fixture success does
not reopen their validation gate.

Final broader checkpoint: `swift test --package-path apple --filter EEGCoreTests`
executed335 tests:331 passed,4 skipped,0 failures in158.2seconds. This run includes
all new comparison kernels. The warm single-channel spectrum benchmark was
4.96ms/window in this test build; it is not end-to-end command latency or hardware
qualification. The test suite did not obtain missing trained Cortex fixtures.

## Singular fitting, sensitivity and error sets — 2026-10-11

| Area | Implemented comparison subset | Remaining qualification |
|---|---|---|
| Singular PCA | Shared symmetric PSD eigensolver preserves zero roots; pooled counts drive low-epoch clipping before rank selection. All-zero roots return nil basis. | Independent LAPACK/sign policy; negative-root rejection is our supported-domain policy. PSD projection now reaches scatter construction and bounded canonical retry; singular final class densities remain explicitly rejected. |
| Sensitivity configuration | Fresh parsed-input resolver: nonempty INI map takes precedence over JSON; aliases/collisions, versions, selected-list refresh and API four-value 1…10 boundary. Existing class-weight lookup/fallback is reused. | No guessed lookup table. Qt file/token/QVariant conversion and repeated populated-map loading are outside this explicit-input boundary. |
| Error-set cache | Ordered action/channel key, shared payload identity, reuse counts, least-used eviction with lexical ties, zero maximum uncapped under our explicit storage limit. | No vendor database serialization or guessed noisy-channel detector. |
| Noisy detection overload | Base route without channel intersection; cache lookup before maximum check; duplicate IDs count; real rebuild callback; cache insertion/reuse or empty invalid result on rejected fitting. | Full noisy-specific refitting is not recovered. The traced manager run passes an empty noisy-ID vector, so that caller does not establish active channel-noise handling. |
| Processed feature routing | Contact-invalid features are withheld; optional background subtraction produces a single vector consumed by auto-neutral, training and detection. Original features are retained separately. | Corrects the previous checkpoint's original-detection-vector interpretation. This is internal comparison orchestration, not a replacement live detector. |

Evidence directories: `singular-continuation-20261011`,
`sensitivity-continuation-20261011`, `error-set-continuation-20261011` and
`noise-orchestration-continuation-20261011` and
`projection-singular-continuation-20261011`. Every implemented branch cites
static function bodies; the captures contain no vendor learned assets.

No new vendor asset is needed to implement these arithmetic/state contracts.
Exact comparison with a participant's deployed classifier still needs actual
feature settings, trained transforms/Gaussians and synchronized reference outputs.
The checked training store was empty; unavailable fixtures remain skipped.
There is no claim of full Cortex parity, psychological validity or production
readiness. Acquisition/decoding and the independent live trainer are unchanged.

Final focused reproduction: `swift test --package-path apple --filter 'Reference|Decoder'`
executed171 tests:169 passed,2 explicitly skipped,0 failures. Shared projection
arithmetic is used by PSD fitting and the independently validated SPD density
path; no duplicate projection formula is retained. Full core verification is
recorded in the checkpoint evidence log.

The broad core run executed361 tests:357 passed,4 explicitly skipped,0 failures.
It preceded the final PSD-intermediate runtime projection adjustment; the final
171-test focused run covers every affected reference kernel, including both new
complete singular fitted-workflow and runtime-subspace cases. Original
measurements and final singular-density rejection remain intact.

## Ordinary noisy-miss rebuild and training persistence — 2026-10-11

The noisy overload calls the ordinary builder with append=false. The builder
has no noisy-ID argument or demonstrated channel mask; it may reuse the ordinary
action cache. `ReferenceClassifierRebuild` now composes the actual fitting kernels
and models inactive-action, missing-class, fitted, rejected-fit and cache-hit
routes. It loads feature slots before Gaussian slots and writes no new epochs.
Its own numerical limits and value-cache representation are explicit boundaries.

`ReferenceTrainingDatabase` implements ordered typed Gaussian/feature loading,
empty placeholders, append/pooling, transposed matrix storage, latest-row
retention and sequential partial writes. It deliberately owns no vendor disk
codec. The true-append builder saves features then Gaussian data before fitting;
that full branch remains an orchestration gate.

Classifier persistence uses a typed `cognitiv-classifier` profile property,
separate from both caches and the explicit ten-field JSON converter. Load clears
the previous classifier before checking the property. JSON exports UInt64 counts
as doubles but imports signed integers; lossless interchange is not assumed.
Nested conversions and actual profile encoding remain open. No mock save/load
success is introduced.

Evidence: `refit-builder-continuation-20261011`,
`training-persistence-continuation-20261011`,
`persistence-cache-continuation-20261011`. Focused reproduction executed180
tests:178 passed,2 absent matched-Cortex fixtures skipped,0 failures. Typed
store→actual fit→Gaussian scoring→cache reuse is analytically checked.
No vendor learned assets were required. Matched trained-profile predictions
and complete disk roundtrip remain unverified; acquisition/live trainer unchanged.

Broad core regression executed370 tests:366 passed,4 skipped,0 failures
in154.24seconds. Final focused180-test run additionally covered the last two
rebuild failure/noisy-miss composition checks added after broad compilation.

Further persistence bodies connect typed Classifier QVariant to profile JSON,
cache update, NoSQL metadata/attributes calls, queued worker, JSON bytes,
compression, encryption and file save. Queued invocation success is not durability:
its return is ignored and the wrapper immediately returns0. Worker retries only
0x3303 up to six calls and emits final saveDone status; encryption failure is
0x3304. Actual compression/encryption/file bodies and inverse profile decoding
still require tracing. Valid wrong-type QVariant conversion may return a default
classifier while load reports type validity; no reliable model roundtrip follows.
These findings are evidence only, not a copied vendor codec.


## Disk codecs, inverse loading and training-save composition — 2026-10-11

This checkpoint supersedes the append/codec/inverse gates in the preceding
checkpoint for the explicitly bounded comparison contracts below. Acquisition
and the independent live trainer are unchanged.

| Area | Body-backed implementation and validation | Remaining boundary |
| --- | --- | --- |
| Compression and encryption | Gzip framing, CRC32/ISIZE, gzip/zlib inverse and IV-prefixed AES-256-CBC with explicit caller keys. Independently generated known answers cover valid envelopes and malformed padding. | Embedded 37-byte vendor salt/key derivation is excluded. Strict complete-stream parsing and resource caps are our documented policies. CBC is unauthenticated and is a comparison codec, not our recommended production storage format. |
| Matrix/classifier inverse | Row-major matrix schema, nested weight/mean/variance conversion, ten classifier fields, signed count import and bounded unsigned-vector conversion. Own JSON→gzip→AES→inverse JSON/classifier roundtrip. | Qt fractional/overflow cases, full Armadillo materialization and runtime field compatibility remain explicit gates. Schema acceptance does not imply a valid model. |
| Gaussian bank/profile inverse | GaussianData/Algebra fields reuse existing bank types; UInt32 timestamp bits survive signed JSON. Profile object dispatch follows Matrix→GaussianAlgebra→Classifier. Rejected nested distributions and omitted properties are observable. | Our supported row-statistics shapes are narrower than vendor generic matrices; partial bank schema acceptance is not training acceptance. |
| Training acceptance | True append composes pending columns, typed feature/time and Gaussian writes, actual fitted transforms, cache invalidation and acceptance cleanup. Saves precede fit rejection, preserving the traced partial-write behavior. | Count/action/brain-map/settings operations remain explicit callbacks; no database transaction or durable file save is fabricated. |
| Load/save IO | Cache miss checks metadata then attributes and caches only success; write worker retries only0x3303 up to six calls. Completion distinguishes file-write error from subsequent metadata-write error. | Direct vendor QFile save has no demonstrated atomic replacement or fsync guarantee. Callback success is not a durability receipt; complete application DB/locker scheduling is not implemented here. |

The strict padding check was necessary: CommonCrypto's default PKCS7 handling
accepted independently authored malformed envelopes that OpenSSL rejected.
Decrypting raw CBC blocks and validating every final padding byte preserves the
traced EVP finalization semantics; the original rejection fixture was retained.
A separate test caught an ambiguous Swift UInt64→Double initializer and the
conversion now explicitly uses numeric conversion rather than a bit pattern.

Evidence directories: `disk-codec-continuation-20261011`,
`inverse-profile-continuation-20261011`, `profile-io-orchestration-20261011`,
`training-save-orchestration-20261011`. Reproduction:
`swift test --package-path apple --filter 'Reference|Decoder'` and
`swift test --package-path apple --filter EEGCoreTests`. Final counts and full
logs are pinned in the training-save checkpoint evidence.

No vendor binaries, model values, credentials or embedded salt are bundled.
Exact vendor-file compatibility needs the salt-derived key; it is not necessary
for caller-key codec verification. A trained Cortex profile and synchronized
intermediate/prediction outputs are still missing for exact trained-profile
comparison. Full physiological mental-command parity is not established by
these offline tests.


## Runtime fields and database/locker orchestration — 2026-10-11

The bounded runtime-field gate from the preceding checkpoint is now resolved
against actual body use, including Armadillo transpose materialization.
`ReferenceRuntimeProfile` selects uniqueFeatureIndices in stored order, maps
coeff/pcMeans to PCA, retains the leading numOfValidFeatures PCA columns, then
maps eigenvec/meanTot to the canonical transform. Gaussian weights are M×1,
means D×M with components in columns, and covariance matrices share component
order. classRefIDs, channelInUse and useCount remain metadata. Priors and neutral
scale are classifier-state inputs outside the ten-field serialized envelope;
no values are invented. Supported dimensional, numerical and shape gates are
explicit and schema acceptance alone never creates a usable classifier.

An independently fitted signature survives typed JSON, caller-key gzip/AES,
inverse loading and runtime inference with unchanged scores. Asymmetric mixture
columns and PCA truncation have analytic checks; invalid selectors/shapes fail.
The adapter reuses existing Gaussian math and does not alter acquisition or the
independent live trainer. No vendor trained data or observed predictions were
available for an exact learned-profile comparison.

| Orchestration | Body-backed contract | Qualification boundary |
| --- | --- | --- |
| FileLocker | One tryLock, separate isLocked gate, diagnostics on failed acquisition, unconditional unlock/disposal. Read/save append .lock and pass1000ms; failed lock gives raw3→attribute error0x3303. | Explicit backend callbacks; Qt stale-lock/OS internals and cross-process durability are not reproduced or qualified by callback tests. |
| Profile-key locks | Idempotent ASCII key membership, observed training/neutral key lists; changed locked QVariant gives a diagnostic but writes proceed. | Advisory, not exclusion or authorization. Equality is supplied explicitly; overlap exposes the observed non-refcounted behavior. |
| Cache/save | Publish cache before metadata then attribute write; no rollback shown. Queued invocation outcome is exposed separately from vendor-reported0. | No successful-enqueue/durability inference; queue/thread/driver implementations remain separate dependencies. |
| Synchronous save | Retry file0x3303 at most6 calls; successful file write immediately calls UUID-only metadata helper and propagates its error. | Corrects the earlier tentative scheduling description. No cross-file/database transaction is shown. |
| Document write | Acquire driver/error, retry only0x3102 at most10 calls, sleep5ms after each busy result including the last; changes notified only on zero plus updater/flag. | Physical driver persistence, full TrainingProfile metadata schema, Qt scheduling and application-store qualification remain unverified. |

Evidence: `runtime-field-continuation-20261011`,
`database-orchestration-continuation-20261011`, `file-lock-continuation-20261011`,
`profile-lock-continuation-20261011`. Final focused/core logs and counts are
recorded in the database checkpoint manifest. No additional vendor assets were
needed. Exact vendor-file key derivation still depends on the previously
identified embedded salt, excluded from this deliverable. Trained vendor
parameters/reference outputs remain optional comparison inputs, not runtime
dependencies or bundled assets. Full Cortex or physiological parity is not
claimed.


## Full metadata and real local storage — 2026-10-11

The ten metadata keys and conditional eegChannels initializer are body traced.
Typed wire handling distinguishes raw timestamps/channels and unsupported Qt
coercions. CouchDriver transaction guards and document parse failures are traced;
commit-error propagation and cross-file atomicity are not inferred.

The independent authenticated SQLite research repository now stores metadata,
full fitted classifier and explicit runtime settings atomically. Existing fitting,
codec and inference kernels are reused. Restart/reopen, actual killed-writer
recovery, contention, revisions, authentication and fault boundaries are tested.
This does not replace the live trainer or qualify physiological commands.
See [complete storage contract and reproduction](REFERENCE_LOCAL_STORAGE.md).

Evidence: metadata-schema-continuation-20261011,
database-driver-continuation-20261011, local-storage-continuation-20261011.
No new vendor assets were needed. Qt date/channel normalization, exact trained
Cortex outputs and physical power-loss qualification remain explicit gates.
