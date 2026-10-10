# Training profile metadata wire schema

2026-10-11; static installed M4 arm64 CortexService bodies, SHA-256
`cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`.
No vendor profile data, credentials, storage salt or model assets are included.

## Concrete constructor/exporter evidence

TrainingProfile(QJsonObject) actual constructor101fab0f4 reads seven strings,
two booleans, two dates included among those strings, and a channel list:

| Key | Import/body | Export/body | Our supported contract |
| --- | --- | --- | --- |
| uuid | fab1e8..220, QJsonValue::toString | fabf60, QString JSON | String, non-string/missing projects empty with diagnostic |
| name | fab2a8..2e0, toString | fabfe0 | Same |
| ownerId | fab368..3a0, toString | fac060 | Same |
| deleted | fab428..468, toVariant→QVariant::toBool | fac0e0, bool JSON | Native Bool plus absent/null false; other coercions unsupported |
| loaded | fab4b0..4f0, same | fac160 | Same |
| originalUuid | fab538..570, toString | fac1e0 | String |
| originalProfileURL | fab5f8..630, toString | fac260 | String |
| createdDatetime | fab6b8..710, toString→QDateTime::fromString(format9) | fac2d8..304 via datetime2String | Raw string wire value; date validity/normalization not asserted |
| modifiedDatetime | fab790..7e8, same date conversion | fac39c..3d0 | Same |
| eegChannels | fab864..a04, toArray→VariantList→each QVariant::toString→stringDb2Channel | fac470..578 conditional enum→channel2StringDb→JSON string list | Raw optional string list; no enum/default-list mapping claim |

All nine basic fields are unconditionally emitted. The exporter flag at profile
+b0 skips eegChannels when true; a nonempty source array imports in order and sets
flag false atfaba00, while missing/empty arrays install a runtime global default
list and flag true atfab8e0..930. Therefore absent/default and explicit lists affect
export shape. The default list contents are not recovered here. Our wire contract
keeps absent(nil) distinct from explicit empty([]) rather than pretending to
normalize either to a recovered default; explicit empty reserialization is our
preservation policy, not exact constructor→vendor exporter equivalence.

The channel key is **not guessed**. Static BSS QString1034bcd10 starts zero.
Bounded ARM64 ADRP/add cross-reference scan found accesses101fab864,101fac54c and
101fad4ac. Actual initialization at101fad498..4b0 constructs "eegChannels" and
registers its destructor. Captures: channel-key-xrefs, channel-key-initializer.
The initializer is the unnamed101fac7f4 function; unrelated initialization keys
are not part of the training schema. No account/license schema is reproduced.

## Date and channel helpers

conversion-symbols captures datetime2String101f2498c: isValid false returns empty
QString249ec..9f0. Valid input preserves offsetFromUtc using a fixed-offset
QTimeZone then toString numeric Qt format9 at249dc..e4. Constructor also uses
format9. We preserve original string bytes instead of inventing a Foundation
formatter, timezone/parser normalization, invalid-date or millisecond policy.
This means the wire adapter is suitable for our independent storage, but is not
an exact QDateTime recreation. stringFieldsWithoutStringInput distinguishes
missing/non-string projection from a genuinely supplied string; neither proves
valid date or identity syntax.

channel2StringDb101fc6898 starts with string "UNUSED" and looks up enum in a
runtime initialized map, retaining fallback if not found. stringDb2Channel
101fc697c scans that map and returns enum0 for missing name. The full map and
default list are not recovered; repeated/unmapped names remain raw wire values
in our adapter, not fabricated enum values. Numeric/non-string QVariant string
coercion is not implemented. Unsupported channels/booleans throw explicitly.

## Attributes versus trained properties

TrainingProfileAttributesInternal::toJsonObject101fadc94 emits exactly uuid:
add8 to QString atfadcb4..cbc, key atfadcc4, returnfadd40; no trained properties
are embedded by that exporter. Existing persistence-cache evidence worker
101e218a0 and worker101e75254 store identity separately from the payload object.
Profile-trained properties remain ReferenceProfileCodec's independent object
contract; we do not invent a metadata key containing learned parameters.

## Independent implementation and boundaries

New ReferenceTrainingMetadata.Profile contains typed fields, raw eegChannels,
unknownFields and non-string-input diagnostics. Unknown preservation is **our**
storage policy; vendor constructor accesses specified keys and ignores extras.
encode emits observed basic field types and raw date/channel values; it does not
claim vendor Qt byte order, date normalization, default-list semantics, profile
version constructor behavior or arbitrary QVariant coercion equivalence.
requireIdentity is an explicit independent repository consistency rule and
performs no invented UUID format validation. attributesIdentity exports uuid only.

Three tests cover own values and unknown nested fields, raw invalid/timezone date
strings, duplicate/unmapped channel names, missing/non-string diagnostics,
absent versus empty channel arrays, unsupported coercions and identity mismatch.
No builds run by this subagent; parent coordinates execution.

Remaining exact metadata gates: runtime default-channel list and enum dictionary
contents, complete Qt QVariant Bool/string conversions, exact Qt format9 parser/
serializer behavior, and unsigned-version constructor effects. No vendor assets
were needed; these gates require further code/oracle evidence, not model files.
