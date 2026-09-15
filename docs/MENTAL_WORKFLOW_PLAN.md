# Ordered mental-command implementation plan

Scope: independent experimental EPOC X processing, not a recovered Cortex model. Preserve the existing raw decoder and acquisition. Native capture and Python reference files are explicitly adapted into one versioned processing contract; live/replay/training/evaluation must call the same window/feature/model functions.

1. **Evidence inventory.** Link actual symbols separately from inspected bodies; record unknown parameters/model assets. Classify vendor infrastructure separately. See PARITY_ROADMAP and mental reference trace.
2. **Canonical input and validity.** Immutable ADC/uV data, observed128Hz configuration, monotonic receive timing, sample indices/epochs, continuity and transport-state provenance. Reject missing metadata, unsupported modes, incomplete/gapped windows. Preserve all raw measurements.
3. **Deterministic windows/features.** Nonoverlapping2-second windows; documented spectral features and artifact flags. Own parameters must be tagged as independent design choices, not recovered vendor constants. Same code for replay and training.
4. **Personalized model lifecycle.** Neutral plus named trained task classes; explicit accepted/rejected trials; training-only scaling, feature selection and PCA; regularized Gaussian scoring; versioned profile and retraining lineage. Never manufacture a profile from uncertain labels.
5. **Rejection and event contract.** Invalid windows, insufficient profile validation, ambiguous/out-of-distribution scores and insufficient persistence produce `no_reliable_command`. Experimental candidate scores remain separately labeled. No OS input side effects.
6. **Offline evaluation.** Whole-recording/session holdout, canonical-data duplicate detection, fixed preprocessing, confusion matrix, precision/recall, uncertainty, latency and neutral exposure. Document artifact dependence and missing ordinary-activity evidence.
7. **Prospective qualification.** Only then request a precise participant task with verified cues/labels; train and test in separate sessions. Ordinary activity and ocular/jaw/motion controls needed before neural-command claims.
8. **Consumer integration boundary.** Versioned read-only application events, explicit provenance and profile versions. Apple/Cast adapters remain outside acquisition and disabled until their own authorization/safety/validation gates pass. No Cast changes in this work.

Current evidence cannot satisfy step7: the latest cued sensory-state session had uncertain participant labels and mixed posterior alpha behavior. It is retained but excluded from training/evaluation. Compiler/unit-test success is not physiological validation.

Native dataset loading now checks exact cross-session excerpts as well as complete
recording hashes. See [the algorithm, boundaries and tests](DATASET_EXCERPT_CHECK.md).
Saved profiles still cannot exclude partial reuse of historical sources absent
from the evaluation manifest; passing the check is not an independence claim.
