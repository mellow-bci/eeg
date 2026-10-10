# Channel metadata comparison adapter

Scope: installed CortexService arm64, SHA256 `cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`. Static LLDB disassembly only; no process execution, profile assets, model weights, credentials or binary bundled. This vocabulary does not qualify hardware: it includes electrode names, motion/marker fields and counters. EPOC X remains the independently verified hardware boundary.

## Proven table and lookup

`channel2StringDb` at `0x101fc6898` and `stringDb2Channel` at `0x101fc697c` both read map pointer `0x1034c0248`. A bounded ADRP instruction scan identified its initializer store at `0x101fd6c24..28`, inside initializer `0x101fd47b8`.

`db-map-initializer.txt` records all 179 stack pairs, stride 0x20 beginning sp+0x18; every integer store and immediately following QString UTF-8 literal is listed in `channel-pairs.tsv` with both addresses. Their IDs are exactly 0...178, each once. `0x101fd6c2c..54` inserts all 179 pairs with helper `0x100010c3c`. The helper compares unsigned IDs and assigns the value for an existing key; this concrete initializer has no duplicate IDs. Its strings also are unique. Sorting by ID is therefore equivalent to the populated map for lookup.

`channel2StringDb` prepares fallback `UNUSED` at `0x101fc68b0..c0`, searches the map with unsigned enum comparison, and copies a found string from node+0x28. `stringDb2Channel` traverses in ascending map order, calls `0x10000df44` for equality and returns node+0x20 at `0x101fc6a0c`; not found returns zero at `0x101fc6a04`. Equality helper compares lengths and tail-calls `QtPrivate::equalStrings(QStringView, QStringView)`, with no case-folding or normalization. Adapter compares UTF-16 units. Actual names `FP1` (117) and `Fp1` (39) are distinct.

Crucial asymmetry: unknown string -> enum 0 -> `LA`; unknown enum -> `UNUSED`. `UNUSED` itself has known enum ID163. These vendor comparison semantics are intentionally visible, not a data-repair policy.

## Default profile list and omission

`TrainingProfile(QJsonObject)` at `0x101fab0f4`, channel branch `0x101fab864..0x101faba04`, reads `eegChannels` as array -> QVariant list -> strings -> `stringDb2Channel`. Nonempty inputs append IDs preserving order and duplicates, then clear flag profile+0xb0. Missing/empty array copies global list `0x1034bcee0` and sets that flag at `0x101fab92c..930`.

Initializer `0x101fad914..990` allocates 14 UInt32 entries, copies first12 from `0x102fd6a74`, and stores packed103/106 as last two. The readonly constant capture and instructions prove ordered IDs:

`40,43,45,51,54,64,69,77,82,92,95,101,103,106`

Mapped via the actual table: `AF3,F7,F3,FC5,T7,P7,O1,O2,P8,T8,FC6,F4,F8,AF4`.

Exporter channel branch `0x101fac470..478` omits `eegChannels` when flag profile+0xb0 is true; explicit nonempty list serializes every mapped name. The adapter returns `exportedNames=nil` for omission, not an empty serialized list.

## Independent implementation and limitations

`ReferenceChannelMetadata` is a separate comparison adapter. It accepts the string-only channel array projected by existing `ReferenceTrainingMetadata`; arbitrary QVariant coercions remain unsupported there. Raw metadata round trips still preserve unknown names and empty arrays. No repository storage path is changed and normalization never occurs automatically.

Three tests cover all179 vocabulary round trips, significant case, default order and omission, unknown string/enum asymmetry, duplicate/order preservation and unchanged raw wire metadata. Parent owns test execution. Static body evidence establishes this installed-build schema; it is not a measured execution comparison against every vendor branch, physiological validation, or exact-parity claim. No additional vendor asset is required.
