# Offline validation, 2026-10-11

Installed reference: arm64 CortexService SHA256 cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a. Read-only static function bodies; no runtime attach, learned asset extraction or acquisition changes.

`swift test --package-path apple --filter EEGCoreTests`: **487 tests, 4 skipped, 0 failures**, 157.442 seconds. Full output: core-tests.log. The skipped checks require external evidence/environment and are not successes. An earlier build failed at a test-only shorthand CQ recipe factory; it was corrected to the explicit ReferenceTypeSevenCQRecipe.current factory before the passing build.

Covered new tests: converted runtime recipe resolution; manager append/removal and feature gate; raw workflow consumed-without-features; CQ packet gates, slot persistence, batch-final broadcast and detector quality minima; subscription cursor/search-result/drain rules and outer-to-inner cadence integration. Existing raw training/save/reload, persistence, fitting and acquisition-related core tests also passed.

Reproduce from repository root with the command above and `python3 tools/render_capability_matrix.py --check`. No external model asset is required for this offline suite.

These tests use authored numerical packets/blocks and supplied search outcomes. They do not prove full timestamp search/interpolation equivalence, real contact transitions, actual loaded Cortex profile selection, physiological mental-command accuracy or full parity. Working BLE acquisition/decoding and independent live trainer were not replaced. Same-input/same-trained-profile Cortex outputs remain unavailable; no vendor model assets were added. Independent bounds, malformed-input rejection and discontinuity resets remain labeled separately from traced vendor behavior.
