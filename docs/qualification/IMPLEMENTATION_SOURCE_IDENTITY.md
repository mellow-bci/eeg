# Evaluation implementation source identity

Native evaluation receipts now include `implementation_source` with schema
`eeg.core-source.v1`, a SHA-256 digest and the input file count. The canonical
EEGCore receipt builder supplies this field for both native UI and CLI. This is
an additive provenance field; the evaluation algorithm remains
`native-labeled-evaluation-12`. Older receipts do not contain this evidence and
must not be treated as identifying an implementation source snapshot.

## Construction

The Swift package build-tool plugin declares all EEGCore source files, the
package manifest, plugin source and generator source as build inputs. Its output
is a generated Swift enum compiled into EEGCore. Swift Package Manager and the
Xcode app's local package dependency use the same plugin. No Git, network,
Cortex process, model asset or credential is used.

The generator sorts package-relative paths, then hashes fields in this order:
UTF-8 schema string; each UTF-8 relative path followed by exact file bytes.
Every field is preceded by its byte length encoded as an unsigned 64-bit
big-endian integer. Absolute checkout paths and modification times are omitted.
The generated file is outside the input source tree and is not itself hashed.
The plugin declares inputs and output so a source change invalidates generation.

This identifies input bytes read by the generator, **not a reproducible binary,
a signed attestation or an atomic filesystem snapshot**. It excludes app/CLI
frontends, tests, docs, external build flags, compiler, SDK, signing and host
state. Avoid concurrent source edits during a build. It does not prove correct
algorithms, clean Git state, authorship, hardware validation or mental-command
performance. Full qualification still requires saved recordings, profiles,
configuration, receipts and the corresponding environment description.

## Reproduction and checks

```sh
swift build --package-path apple
python3 tools/check_source_identity.py "$(swift build --package-path apple --show-bin-path)/EEGSourceIdentityTool"
swift test --package-path apple --filter LabeledEvaluationTests
./apple/build-native.sh all
```

The independent Python framing oracle checks repeated generation, relocation,
file-content and filename changes, and compares actual plugin output against
all current core Swift sources plus the three build definition files. Receipt
tests verify the compiled identity is serialized and repeated receipts agree.
CI runs the oracle after native tests. These tests use synthetic data only.

Local validation on 2026-09-15: the oracle passed, all 12 labeled-evaluation tests
passed, and macOS, iOS simulator and visionOS simulator builds succeeded. This
is build/offline evidence; it does not qualify hardware operation on those
platforms.

The complete 24-trial synthetic fixture was regenerated with this identity and
passed `tools/check_trial_association_cli.py`: CLI receipt bytes matched the
canonical evaluation receipt, including source and outcome accounting. The
rebuilt macOS app was launched and inspected in Live signals: disconnected,
zero samples, no source loaded, Record disabled. No Bluetooth discovery or
physiological capture was performed during this check.

CI run [34938754603](https://github.com/autonomy-cloud/eeg/actions/runs/34938754603)
completed successfully for `06dbfdeb90db61d89ea50be2e655e81d93836430`.
The independent source-identity check passed in that runner at 06:56:12 UTC on
2026-09-15. This is CI evidence for that revision, not later changes or hardware.
