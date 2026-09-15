# Mental-command caller and density-loop evidence

This follow-up re-examines the archived, bounded arm64 disassembly described in
[MENTAL_REFERENCE_TRACE.md](MENTAL_REFERENCE_TRACE.md). It does not run Cortex,
extract trained assets or change the independent classifier. All twelve trace
files matched their manifest SHA256 hashes and byte lengths on 2026-09-15.
Hash agreement establishes which captured text was inspected, not correctness
of the interpretations below or the identity of a currently installed binary.

## Canonical-transform argument

In [classification-run.txt](../evidence/mental-command-reference/classification-run.txt):

1. `0x100b1deac` saves the classifier reference in `x21`.
2. `0x100b1df50`–`0x100b1df68` subtract values at classifier offsets `0x390`
   and `0x398`, arithmetic-shift the difference by seven, and multiply by
   `0xaaaaaaaaaaaaaaab`, retaining the result in `x22`.
3. The low 64 bits of this multiplier times three equal one. For a valid,
   nonnegative collection extent divisible by `0x180`, this sequence yields
   the number of 384-byte elements. This interpretation is corroborated by
   the later iteration stride, rather than inferred from a symbol name alone.
4. `0x100b1e130` passes that unchanged count as `x3` to `canonicalTransform`.
5. In [canonical-transform.txt](../evidence/mental-command-reference/canonical-transform.txt),
   `0x100b1ece8` retains `x3`; `0x100b1ecfc` tests count minus two and
   `0x100b1ed10` forms count minus one for the selected matrix extent.

The same caller count controls a later loop: `0x100b1e358` saves its bound in
`x27`, `0x100b1e390` advances the element byte offset by `0x180`, and
`0x100b1e394` compares the iteration index with that bound. At
`0x100b1e3b8`–`0x100b1e3dc`, the current element and its `+0xb0` and `+0x160`
subobjects are passed to `probabilityCalculation`.

**Established:** the canonical extent is tied to the count of the same
classifier collection whose elements feed probability calculation. The caller
requires that count to exceed one (`0x100b1df6c`–`0x100b1df70`).

**Not established:** the semantic label of each element, whether one element
always equals one user action, or which element is neutral. Thus “collection
count minus one” is supported; an unconditional “number of actions minus one”
claim still needs collection-construction and action-mapping evidence.

## Probability routine: weighted repeated density evaluations

In [probability.txt](../evidence/mental-command-reference/probability.txt):

- `0x100b1ef94`–`0x100b1efb0` preserve the input parameter objects in `x21`,
  `x22` and `x20`. The named signature identifies the last as a vector of
  Armadillo matrices; the other two are matrices, with unresolved semantics.
- `0x100b1f0c0` loads a loop bound from the first word of the matrix held in
  `x22`; `0x100b1f0e0`–`0x100b1f0f0` increment the index and advance a matrix
  element offset by `0xb0`. Actual iteration counts are runtime data.
- `0x100b1f164` selects a vector element. `0x100b1f170` constructs `MvnpdfTxf`
  from a prepared matrix and this element.
- `0x100b1f184` applies that transform to the input matrix. `0x100b1f1c4`
  applies the same transform to the prepared matrix. Both pass boolean zero;
  the meaning of that boolean is not established here.
- `0x100b1f218` loads a scalar at the current index from the matrix data held
  in `x22`. `0x100b1f228` performs a fused multiply-add using that scalar,
  the first returned density value and the first output accumulator.
  `0x100b1f240`–`0x100b1f254` repeat the weighted accumulation for the second
  transform result and the second accumulator.

**Established:** the body supports repeated Gaussian-density transform
construction/application and two weighted accumulated outputs. The same indexed
scalar weights each pair of results.

**Inference:** this is consistent with a mixture-like Gaussian score, potentially
with a reference-density term. It is stronger evidence than merely observing
`MvnpdfTxf`, but does not establish a normalized Gaussian mixture distribution.
Weight signs/sums, parameter meanings, covariance structure, singular handling,
actual component counts and the downstream interpretation remain unresolved.
It does not prove that a live EPOC X profile uses multiple components.

## Posterior scalar ownership

The caller preserves its `Classification` object pointer at stack offset eight
in `0x100b1e320`, restores it to `x20` at `0x100b1e434`, then loads `d0`
from that object's `+0xb0` at `0x100b1e4e8` before calling
`posteriorCalculation` at `0x100b1e4f8`. This narrows the scalar's source to
classifier-execution object state. It still does not identify a sensitivity
meaning, default value, units or user-setting mapping.

## Consequence for the independent stack

Our v2 profile fits one regularized diagonal Gaussian per class after selected
features and PCA (`processing/mental.py`, native `MentalTraining.swift`). It
does not implement the vendor's canonical projection or the repeated weighted
density path above. Preserve this explicit algorithm boundary in comparisons.

A future independently designed multi-component candidate requires a new
versioned recipe, component-selection rules fitted only on training sessions,
stable likelihood calculations, and session-held-out comparison against the
current single-Gaussian model. More components are not presumed better. Do not
change the current pipeline or import unknown weights merely to resemble this
reference. The immediate qualification priority remains real task/neutral and
artifact-control sessions for the existing end-to-end workflow.
