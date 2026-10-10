# Ordinary rebuild inside noisy detection

Static arm64 CortexService SHA256 `cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`. Capture includes buildClassifier, init and classifier copy helper; no execution, vendor binary or learned assets bundled.

The previously captured noisy overload at 0x100b32444 invokes ordinary buildClassifier(profile,false,clone) at 0x100b32970. No noisy-channel IDs are passed and no feature masking is shown. Manager run supplies an empty noisy-ID vector. This checkpoint does not invent a noise-specific feature removal or assert it is active in that caller.

Builder 0x100b2f64c checks the configured training action is in current ordered actions, then looks up ordinary action cache. Cache hit increments use count and copies classifier to output, bypassing database loads. On miss, features/timestamps load before Gaussian classes. Any class with empty distribution bank prevents fitting. GaussianTraining::run receives the same manager feature metadata. Successful fit writes actions, resets use count, copies fitted classifier to output and inserts ordinary cache entry. appendNewData=false writes no new training epochs. The copy constructor at 0x100b1ba40 includes useCount at offset0x460.

The append=true branch additionally combines pending data, updates the selected training class and writes features/timestamps at 0x100b2ff34 followed by Gaussians at 0x100b2ff94 before testing the missing-class flag and fitting. Save return values are ignored by this body; no transaction is inferred. Full append-branch composition is not implemented in the new rebuild helper.

ReferenceClassifierRebuild composes existing pooling/selection, PCA, scatter, bounded canonical retry and runtime projection into actual fitted signatures. Its run function covers the false-append path, with explicit typed loader callbacks. ReferenceTrainingDatabase supplies independently owned typed storage contracts; it is in-memory, not recovered vendor disk encoding. Cache value semantics and our numerical/resource policies remain documented comparison boundaries.

Tests verify typed bank→fit→Gaussian scoring→ordinary cache reuse and inactive/untrained failure. Focused Reference|Decoder suite:180 executed,178 passed,2 absent Cortex fixtures skipped,0 failed. These are analytic reconstruction checks, not matched deployed-profile verification. Exact noisy refitting, persistence byte format and trained Cortex prediction equivalence remain open; no trained assets were needed for this checkpoint.

Broad EEGCoreTests run:370 executed,366 passed,4 unavailable fixtures skipped,0 failures in154.24s. It preceded the last two added rebuild edge/noisy-composition tests; final180-test focused run covers both. This chronology does not establish hardware/profile parity.
