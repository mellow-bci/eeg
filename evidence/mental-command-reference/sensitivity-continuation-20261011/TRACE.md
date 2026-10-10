# Sensitivity configuration reconstruction

Reference: installed CortexService arm64, SHA-256 `cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`. Static LLDB disassembly only. This is configuration semantics, not recovered psychological validity or trained-profile parity.

## Proven path

| Stage | Body evidence | Result |
| --- | --- | --- |
| INI parse | Config::mcSensitivity `0x101f1feb4`; `config-loading-normalize.txt` | Child keys are selected by a static prefix; suffix creates the paired values key. Headset type comes from the first QSettings value via `stringToHeadsetType` at `0x101fc8708`. Values string is comma-split (`0x101f20194..1a8`), trimmed, converted with QString::toDouble(bool*) (`0x101f20244..290`); unsuccessful tokens are skipped. Type must be nonzero and parsed list nonempty (`0x101f202c0..2dc`). Return true iff output map nonempty (`0x101f203b0..3c0`). No numerical rescaling/clamp is shown. |
| Config precedence | DetParameters::loadMCSensitivity `0x100b86c70`; `config-loading-normalize.txt` | Nonempty parsed INI takes the entire configuration branch (`86cb0..cc4`). Each entry gets version `configIniFile`. JSON is used only when Config::mcSensitivity returns false; there is no per-headset merge fallback. |
| JSON boundary | Same loader `0x100b86fd4..87130` | Resolved headset enum, nonempty version, sensitivity array. Empty version skips entry. `QJsonValueConstRef::concreteDouble(ref, 0)` at `0x100b870dc..e8` converts array elements, with zero for nonnumbers. Empty arrays are not rejected. The new helper receives already-resolved enums and ordered entries; it does not pretend to implement the Qt string-map parser. |
| Headset aliasing | Core::normalize `0x101fc96c8`; `api-version-map.txt` table `0x102fd6e68` | Mask 0x77 covers types 2,3,4,6,7,8: 2→1; 3,4,7,8→4; 6→5. Type5 and all other Int32 enum values stay unchanged. Table index3 is not used. This mapping is configuration aliasing, not support for untested hardware. |
| Replacement | `map-insertion.txt`, `map-replacement.txt`, helpers `0x100b89c94`, `0x100b8d270` | Existing matching normalized key assigns both QString version (`8d2c8..d0`) and list (`8d2d4..f4`); later entries replace earlier ones. Parsed INI iterates numeric QMap keys ascending. JSON order remains caller-supplied, because object key iteration order is outside the explicit-input helper. |
| Manager setter | `load-set-parameters.txt`, `0x100b39bb4` | Empty map ignored; nonempty map replaces manager+b88; selected list+b90 is not refreshed here. |
| Manager selection | `load-set-parameters.txt`, `0x100b3922c` | Clears selected list at entry (`39240..44`), normalizes headset, copies matching map list (`392b8..d8`). Missing headset stays empty. |
| Getter/version | `load-set-parameters.txt` get `0x100b89380`; `api-version-map.txt` version `0x100b89540` | Manager map getter drops version and returns numeric lists. Version getter normalizes headset and returns stored version or literal `notFound` (`895ec..960c`). |
| Action setting API | `api-full.txt`, API::mentalCommandActionSensitivity `0x100358108` | Set path requires exactly four entries (`358324..32c`), each convertible to int and in 1..10 (`358340..43c`), and stores the four `cognitiv-actionNThreshold` values (`358448..5f0`). Qt conversion is deliberately outside the new integer-only validation boundary. |
| Downstream weights | Existing `../training-bank-continuation-20261011/conversion-class-weights.txt`, `0x100b35ff0..3623c` | Already implemented by ReferenceTrainingBank.classWeights: neutral weight1; exactly ten active table values select clamped threshold−1 lookup. Other table lengths use `10^((threshold−5)/2)`. These are unnormalized class weights, not neutralScale or posterior thresholds. New ManagerState calls this existing primitive. |

## Implementation and test boundary

`ReferenceSensitivityConfiguration.swift` implements the finite explicit parsed-input path, fresh-map resolution, aliases, version lookup, integer action validation, transactional manager-map replacement and selection, and reuse of the existing class-weight scorer. It supplies no default lookup table or vendor profile. Five analytic tests check alias mapping, whole-map precedence, collision replacement, JSON invalid-version/nonnumeric behavior, stale selection, missing-key scoring fallback, API boundaries and finite rejection. `swift test --filter ReferenceSensitivityConfigurationTests`: five tests, zero failures, 2026-10-11.

The finite-value rejection is our supported-domain policy, not a recovered vendor check. Values are not clamped to a guessed probability or sensitivity range. The API's 1..10 action settings and the config's ten-element weight table are distinct contracts.

## Remaining limits and assets

The helper does not parse actual QSettings files, decode the loader's static key QStrings/headset-name map, emulate every QVariant conversion, or reconstruct repeated loading into an already-populated DetParameters map. Its resolve function explicitly starts with a fresh map. Runtime profile integration and comparison against a participant's trained profile are still outside this task. No trained vendor asset was needed or copied. Matching the installed deployment's table mode requires its actual explicitly supplied numeric settings; when absent, the traced exp10 fallback is available. Missing trained PCA/canonical/Gaussian reference parameters remain a separate comparison requirement.
