# Installed metadata scalar conversion reference

The already captured TrainingProfileInternal constructor uses QJsonValue::toVariant then QVariant::toBool for deleted/loaded. This continuation inspects installed QVariant bodies and executes an independent synthetic oracle against the installed QtCore 6.8.3 framework on M4. The framework SHA256 is 72c5813bd716181e3388b50c43b8a2172037da6834ffd05132c9d3144ec54721 (same identity as the date continuation). No Cortex account, profile, headset, license path or model is invoked.

Evidence: qt-variant-bodies.txt captures installed arm64 toBool/toString. oracle.tsv and oracle-boundaries.tsv use direct scalar QVariant construction. oracle-json.tsv uses the actual QJsonValue → QVariant route; input-json-cases.tsv and oracle-json-probe.cpp reproduce it. JSON integers can preserve their integer representation: 1000000000000000 converts to a decimal string whereas a direct Double can use exponential notation. Therefore this work does NOT substitute direct-double string formatting for channel/name conversions.

Observed Boolean conversion: empty, "0" and case-insensitive "false" strings become false; whitespace is not trimmed and "no" becomes true. Floating-point numbers convert through qRound64: ±0.49 become false and ±0.5 become true. JSON null becomes false. Empty collections also returned false in the oracle, but general collection conversion is deliberately unsupported in the adapter. Official matching source confirms the scalar rules: https://github.com/qt/qtbase/blob/v6.8.3/src/corelib/kernel/qmetatype.cpp (convertToBool and integral converters), and qvariant.h; qjsonvalue.h, qjsonarray.h, qjsonobject.h and qcborvalue.h establish the probe ABI.

ReferenceTrainingMetadata.decode defaults to strictNative and retains the independent storage contract. The explicitly selected qtBounded mode covers ASCII strings up to 4096 bytes, finite numbers of magnitude at most 2^53−1, native booleans and null. These size/range/ASCII boundaries are our qualification policy, not recovered Cortex limits. Unsupported collections, Unicode case-folding domains, nonfinite/oversized numbers reject. Channel arrays still require strings; unknown metadata preservation and identity matching remain our own policies. Date/channel normalization stays in the separately traced opt-in adapters.

The probe uses minimal arm64 Qt 6.8.3 ABI declarations, with QString returned allocations retained until the short-lived process exits. It is version-specific comparison tooling, not a production allocator or a Qt dependency in EEGCore. Synthetic oracle tables contain deliberate trailing empty fields and whitespace strings; preserve them unchanged.

Reproduce on M4 with the already installed official framework:

```sh
clang++ -std=c++17 oracle-json-probe.cpp -F"/Applications/EmotivApps/EMOTIV Launcher.app/Contents/Frameworks" -framework QtCore -Wl,-rpath,"/Applications/EmotivApps/EMOTIV Launcher.app/Contents/Frameworks" -o /tmp/eeg-variant-probe
/tmp/eeg-variant-probe < input-json-cases.tsv
/tmp/eeg-variant-probe < input-boundaries.tsv
```

Reproduce independent tests: `swift test --package-path apple --filter ReferenceTrainingMetadataTests`. No vendor assets are needed or bundled. Passing these synthetic vectors qualifies the documented scalar domain, not all Qt conversion behavior or a trained mental-command profile.
