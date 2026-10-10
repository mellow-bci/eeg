# Timestamp/interpolation offline validation

`swift test --package-path apple --filter EEGCoreTests`: **498 tests, 4 skipped, 0 failures**, 157.982 seconds. Full output in core-tests.log. Seven new timestamp/search tests and four interpolation tests passed. External-evidence/environment skips are not counted as successes.

Tests cover interval inclusivity, covered empty gaps, cache starts, incomplete search/fallback, dropped cursor integration, nearest-helper ties/sentinels, timestamp-selected blocks through raw diagnostic features, spatial basis arithmetic/jitter draws, counter wrap/distance gates and scalar temporal gaps. Initial authored integration used one channel; median subtraction correctly zeroed it and rejected zero power. The test was corrected to two distinct authored channels; no zero-power floor or production behavior was changed.

Reproduce from repository root with the command above and `python3 tools/render_capability_matrix.py --check`. Runtime BLE acquisition/decoding and independent live trainer are unchanged. All new numerical tests use authored data, not real injected losses or matched Cortex results. Spatial helper does not qualify Insight hardware or establish EPOC X applicability. Explicit random draws do not recover Qt global RNG. Temporal scalar math does not implement a complete package/time/CQ pipeline. Newly captured CQ/time/round/cache body findings are evidence only where no adapter exists.

No vendor model asset is required for these adapters. Same-profile inference agreement still requires locally held trained comparison parameters and matched Cortex outputs. No binary, credentials or proprietary trained asset is included.
