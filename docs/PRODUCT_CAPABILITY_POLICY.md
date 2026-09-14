# One application, no subscription tiers

User requirement: independently implement the useful capabilities currently scattered
across vendor applications and subscription tiers in one EEG application. All implemented
capabilities are available without plan selection, paid unlocks or subscription checks.
This is a product requirement, not a claim of completed feature parity.

## Availability contract

- Local headset discovery, acquisition, processing, analysis, training, profiles,
  recording, replay, annotations and export require no vendor runtime or account.
- No artificial duration, recording-count, channel, export, profile or model-training
  limits are introduced to differentiate commercial plans.
- Real resource controls remain: storage budgets, bounded buffers, compatible hardware,
  permissions and validated algorithm requirements must fail visibly and honestly.
  Running out of disk is a resource failure, not an invitation to upgrade a plan.
- Research and uncertainty states remain explicit. An unvalidated detector is not made
  authoritative merely because all features are available. Unsupported hardware is
  unsupported until tested, never locked behind a higher tier.
- Optional collaboration, remote APIs, backup/sync and administration must use the same
  recording/profile/event contracts and one permissions model. Local operation remains
  available when offline or without those services.
- Remote services must not silently upload EEG or require a cloud account for local work.
  User-controlled storage, retention/deletion and explicit data destinations are part of
  service design. Access authorization protects data; it is not a subscription tier.
- The implementation does not patch vendor licensing, ship vendor binaries/models or
  depend on vendor services to unlock its own functions.

## Delivery inventory

The authoritative scoped progress remains `capability-matrix.json`. Its useful product
capabilities include device lifecycle, timestamps/loss accounting, quality, filters and
spectra, personally trained commands, validated gesture detectors, carefully defined
metrics, profiles, experiments/markers, recording/replay/export, streaming interfaces
and optional collaboration/storage services. Each must pass its own acceptance criteria.
Vendor billing, entitlement and account internals are not needed for these capabilities.

First complete the independent mental-command workflow and prospective evidence, then
expand capability by capability through the same application and data path. Do not add
parallel setup flows, fake successes or vendor-score names without validated meaning.

The independent trainer has no fixed training-window or task-class count cap. It still
requires sufficient per-class data across sessions and uses memory proportional to the
supplied dataset; out-of-memory is a resource failure, not a feature entitlement. The
fixed feature recipe and validity thresholds are model definitions, not commercial caps.
