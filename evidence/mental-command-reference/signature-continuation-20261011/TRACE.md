# Signature training orchestration

Scope: static arm64 inspection of GaussianTraining::run, combineClassGaussian,
buildSignatureFromPCA and extractChannelInUse. The source executable stays on
M4; no executable, vendor model assets, profiles or secrets are bundled.
Supporting captures and their digests are listed in `manifest.json`.

## run: ordered stages and failure boundaries

The complete run body is already in
`profile-followup-20261010/gaussian-training-entry-selection.txt`
(0x100b42b44–0x100b42fb0). The tail is captured again in
`weights-run-tail.txt` for channel metadata continuity.

- 42b78–42b8c initializes output bool to true, requires at least two 32-byte
  GaussianAlgebra entries; 42b9c–42ba8 requires the metadata matrix nonempty.
  Either initial failure resets bool to false and returns.
- 42c20–42c28 checks source classReferenceID against −1; that branch leads
  to 42f10/42f2c (failure helper followed by brk), not an accepted class.
- 42cb0–42cb4 calls combineClassGaussian with false for every class, in order.
- 42cfc calls runUnivCoordSelection on the pooled vector.
- 42d04 branches on empty selected coordinate vector; no signature build
  occurs on that path, which logs insufficient clean data at 42db4–42e04.
- 42d10 calls buildSignatureFromPCA and 42d14–42e0c copies selected
  coordinates into classifier+0x20.
- 42e14–42e28 stores max(original class count, classifier+0x2e8) in
  classifier+0x3a8; 42e38 extracts channel IDs from coordinate metadata.

This continuation implements the supported prefix and an explicit fitted-artifact
assembly boundary. `ReferenceSignatureTraining.run` requires a fitting callback;
it never supplies dummy centers, identity bases, default priors or a fake fitted
profile. Our reference API throws and returns no partial signature on failure;
this is deliberately safer than exposing the vendor's in-place partial mutation.

## combineClassGaussian

Complete existing body: 42fb0–43254, same supporting capture.

- 42ff0 clears destination data; 42ff8–43004 constructs and appends one empty
  GaussianData. Thus even an empty source has one empty vendor data slot;
  our bounded representation is a nil distribution, not invented statistics.
- 4307c selects output data slot 0; 43084 gets source component count.
- 430c0–430e8 copies accumulated GaussianData into a temporary; 430f4
  reads the next source component; 43108 calls combineGaussian(accumulated,
  next, output, bool) in source order. The existing pooling kernel implements
  the bounded arithmetic, including sequential timestamp averaging/wrapping.
- 43178–43198 preserves the source classReferenceID only when bool is true;
  otherwise it sets destination ID to −1. run always passes false.

Our `sourceClassReferenceIDs` field retains original IDs solely as provenance.
It does not claim those IDs were retained by the pooled vendor classifier.
No pooling duplication was added to the update-bank agent's work.

## PCA builder and unit weights

Complete existing body: `training-followup-20261010/fit-entry.txt`,
0x100b44ca4–0x100b457b4.

- 44ce0 clears classifier before validating at least two input classes.
- 44d90 invokes runPCA; 44d94–44d98 bypasses signature creation if PCA
  matrix is empty. No forced identity/minimum component substitute is allowed.
- 44e28 invokes runCanonicalDecomposition.
- 44e78/44e7c supply shape 1x1 to helper 53bb4 for each canonical covariance
  slot. `weights-run-tail.txt` resolves this helper as an all-ones matrix:
  53c94–53c98 writes binary64 1.0 into its single-element output.
- 45364–45410 copies each canonical covariance into class signature+0xb0;
  4542c–454dc copies the matching ones matrix into class signature offset 0;
  454fc–45518 takes the matching canonical mean from the MANOVA result into
  the per-class mean vector. This proves one unit-weight component for this
  builder path, not a universal rule for imported/multicomponent profiles.

`assemble` validates explicit PCA/canonical centers and bases plus already fitted
canonical class Gaussians, then creates one weight-1 component per class using
the existing strict-SPD density validation. It does **not** derive missing scatter
matrices, PCA global mean/pooled covariance, class priors, neutral scaling or the
full profile lifecycle. Existing kernels support bounded PCA selection and
canonical decomposition, but this API does not pretend their caller recipe is
fully reconstructed. Those fitting artifacts remain explicit prerequisites.

## extractChannelInUse

Complete new function capture: `channel-map.txt`, 457b4–45bd8 (LLDB named
function disassembly includes its full extent).

- 45838 obtains metadata column count; 45860 divides by two. Metadata columns
  form adjacent pairs; the meaning of the second element is not inferred here.
- 4586c reads each selected coordinate. 458a4 visits columns 2*j;
  458b0 reads metadata(coordinate,2*j); 458b4 converts to unsigned integer.
- 458d8–45934 inserts IDs into a unique ordered tree.
- 45944–45998 builds a one-row output; 45a74–45a7c casts ordered integer
  values back to double in tree traversal order.

`extractChannels` preserves even-column selection, truncation toward zero,
duplicate elimination and ascending order. Odd final columns are ignored.
Our bounded conversion rejects negative/nonfinite/out-of-exact-binary64-range
values; it does not approximate hardware saturation or malformed-memory behavior.

## Tests and remaining evidence

Run: `cd apple && swift test --filter ReferenceSignatureTrainingTests`.
Analytic tests cover a three-distribution ordered fold (including timestamp
order), class ID flag, empty fold, 20-feature rank/slicing/channel union,
fractional channel casting/odd columns, validated unit-weight assembly,
malformed input rejection and propagated fitting failure.

These tests do not establish vendor numerical output equivalence or mental
command accuracy. Remaining work: trace and connect complete global PCA pooling,
canonical scatter/mean recipe and epoch handling; derive classifier priors and
neutral parameters from their actual caller; compare trained reference artifacts
and output on matching recordings. No vendor assets were required for the
orchestration arithmetic inspected here.
