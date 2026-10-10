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

Explicit-covariance PCA eigenbasis arithmetic and Gaussian distribution
projection now have analytic tests. These are bounded training primitives,
not a completed Cortex-compatible trainer. Per-feature pooling masks,
feature-ranking formula, PCA rank policy, MANOVA canonical fitting and neutral
autosampling configuration remain open. The existing independent trainer is
not substituted for those unresolved stages. See
`evidence/mental-command-reference/training-followup-20261010/TRACE.md` for
function addresses, capture coverage, numerical choices and ordered gates.

The focused Reference/Decoder suite executes 37 tests with two explicit skips
and zero failures. No matched trained Cortex profile has become available;
exact mental-command pipeline parity is still unverified.
