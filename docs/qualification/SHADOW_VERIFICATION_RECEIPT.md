# Exportable native shadow verification receipt

The profile's **Offline inference check → Verify recorded live outputs** flow now
offers **Export comparison receipt** after a comparison returns a report. This
exports the already-computed result; changing the window-limit field afterwards
does not relabel the result with an unexecuted setting. The limit is captured in
the report itself. The export uses the same JSON document adapter as labeled
evaluation. It does not require a vendor process or a cloud account.

## Canonical contract

`EEGShadowVerification.Report.jsonData()` is the sole serializer. The v1 schema
is `eeg.shadow-verification.v1`, with algorithm `native-shadow-verification-1`.
Fields include:

- Full recording SHA-256, selected run ID and validated profile ID.
- The actual maximum-window limit, replay/recorded window counts, mismatched and
  missing ordinal lists, observed stop and its reason (null when absent).
- Complete output match and the separate same-implementation match.
- Recorded implementation digest (null when absent), identity comparison status,
  and the current verifier's compiled source schema/digest/input count.
- Explicit false system-control and hardware-validation flags, plus definitions
  of comparison scope, limits, source identity and required reproduction inputs.

Serialization uses the existing deterministic `PythonCompatibleJSON` encoder.
No wall-clock generation time, local absolute path or random receipt ID is added.
Equivalent results under the same source and inputs yield identical bytes.
Serialization checks cancellation before beginning. A verifier failure yields no
report; a nonmatching but structurally valid report remains exportable evidence.

Retain the exact original recording, profile and verifier source separately.
Profile IDs cover validated profile content; recording hashes identify exact
file bytes. The receipt does not bundle those inputs, authenticate them, prove a
reproducible binary, or establish physiological performance. Source identity
excludes frontends, compiler/SDK and build flags. A changed source build may
legitimately change the receipt even when numerical outputs match.

## Tests and qualification boundary

The test creates finalized synthetic recordings using the queued writer and
actual live consumer, then runs the canonical verifier twice. It checks byte
equality, independently computed recording hashes, profile/run selection,
captured limit and counts, all mismatch/missing lists, null stop evidence and
disabled action/qualification flags. Four cases cover matching output, altered
output, missing output and absent stop. Source file bytes must remain identical.

```sh
swift test --package-path apple --filter ShadowVerificationTests
./apple/build-native.sh all
```

All eight shadow tests passed with zero failures in 5.474 seconds on 2026-09-15.
macOS, iOS simulator and visionOS simulator builds succeeded for the new UI path.
This is offline synthetic receipt qualification. Native picker interaction and
exported-file visual/UI verification remain separate checks; no hardware or
participant experiment was performed.

## macOS picker qualification

On 2026-09-15 the built app inspected a synthetic saved profile, selected its
269-sample recording and run, and compared with a one-window limit. The UI showed
one replayed/recorded window, zero missing/mismatched windows, matching core source
and disabled system control. The actual native save dialog exported a 1,522-byte
receipt. Its bytes matched the canonical test receipt exactly:
`cc3d81d56ce68694af3a5da84027c61d741c0f5cbd2387e94307c724416bf091`.

[Machine-readable observations](native-ui-shadow-export-20260915.json) identify
the source, profile, result and qualification limits. The original two-file
library was hash-checked before/after and restored exactly. Temporary synthetic
recording/profile additions were archived outside the library. No live discovery,
capture, audio cue or participant experiment occurred. Fixture installation was
local setup, not a qualification of the recording import dialog.

An accessibility issue remains: the button text was visible in the screenshot,
but its name was absent in the observed accessibility tree. An explicit label
alone did not resolve this observation; a text/ignore-children experiment removed
the button from the observed tree. Both changes were reverted, and the original
working control rebuilt. This observation is not a completed VoiceOver test or
a claim about all assistive technologies. Accessibility qualification remains open.

To reproduce the exact synthetic input and canonical expected receipt in a new
directory before using the app:

```sh
EEG_SHADOW_UI_FIXTURE=/tmp/eeg-shadow-ui-new swift test --package-path apple \
  --filter ShadowVerificationTests.testDeterministicReceiptPreservesResultsAndReproductionInputs
```

The opt-in test exporter refuses an existing destination and writes only the
synthetic recording, profile and expected receipt. It does not modify the native
application library. A future build's source fingerprint may change its receipt.
