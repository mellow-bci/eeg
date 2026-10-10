# Classifier persistence: exact supported boundary

Static LLDB arm64 reference CortexService SHA256 cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a. No runtime execution, proprietary profile values, binaries or trained assets included.

## Three distinct contracts, not one cache database

Actual symbol lookup returns ClassifierCache constructor/get/put/enable/maximum-size/dirty-removal only; no methods named Database::saveClassifiers/loadClassifiers were found in the queried names. Absence in this query does not prove no indirect serializer exists. The recovered ClassifierCache remains an in-memory map (see ../cache-continuation-20261011). Do not invent a database save/load API for it.

Classifier::saveClassifier (0x100b250a0) accepts an EmoProfile pointer; null profile is a no-op (0x100b250c4→25148). It constructs a QVariant containing the supplied classifier through helper 0x100b251b8, builds key 'cognitiv-classifier' (0x100b250e4), and calls EmoProfile::set at 0x100b25110. This is a custom typed QVariant. This call itself is not JSON serialization; the later profile save path below does invoke the JSON exporter. It is not a database-byte codec. The helper registers a Qt metatype then passes the classifier pointer to QVariant(QMetaType,void const*) at 0x100b25290. LLDB labels the interface address relative to adjacent GaussianAlgebra type symbols; that label must not be used to infer the actual type identity. The body copies classifier fields via helper 0x100b252f8.

Classifier::loadClassifier (0x100b24d04) rejects null profile via branch 0x100b24d28→24e0c; for nonnull profile calls clearClassifier FIRST (0x100b24d34), fetches 'cognitiv-classifier' through EmoProfile::get (0x100b24d68), checks QMetaType validity (0x100b24da8), then converts custom QVariant with 0x100b1c700 and moves/copies into destination through 0x100b24e68. Return uses saved metatype-valid result (0x100b24df4). Invalid property therefore does not preserve prior classifier. No classifier-shape acceptance guarantees follow merely from QVariant validity.

## Explicit JSON schema

Cortex::Detections::toJsonObject(Classifier const&) 0x100b14a80 exports these ten fields:

| Field | Supported value shape | Export site |
| --- | --- | --- |
| weightMeanVariances | array of WeightMeanVariances JSON objects | 0x100b14acc /14b4c |
| classRefIDs | ordered signed-int JSON array | 0x100b14b18 /14bcc |
| uniqueFeatureIndices | Matrix-shaped object through unsigned Armadillo-column conversion | 0x100b14c44 /14c58 |
| coeff | Matrix-shaped double object | 0x100b14cd8 /14cec |
| pcMeans | Matrix-shaped double object | 0x100b14d6c /14d80 |
| eigenvec | Matrix-shaped double object | 0x100b14e00 /14e14 |
| meanTot | Matrix-shaped double object | 0x100b14e94 /14ea8 |
| channelInUse | Matrix-shaped double object | 0x100b14f28 /14f3c |
| numOfValidFeatures | UInt64 converted to JSON double | 0x100b14fb8..fc0 |
| useCount | UInt64 converted to JSON double | 0x100b15038..044 |

WeightMeanVariances exporter 0x100b13edc exports `weight` as Matrix (0x100b13f5c), `mean` as Matrix, and `variances` as an ordered array of Matrix objects from vector member+160 (0x100b13f08..f44). Matrix exporter 0x100b11a94 exports `rows`, `cols`, `elements`: dimension methods rows/cols; elements from Matrix::vector then a parallel QVariant mapping helper 0x100b1735c then QJsonArray::fromVariantList. Armadillo matrix bridge 0x100b11ed4→fromArmadilloMatrix 0x10212d080; unsigned vector bridge 0x100b11f54→fromArmadilloUVec 0x10212d450. Exact matrix flattening/unsigned conversion and asynchronous mapping arithmetic require following those bodies; field names alone do not recover them.

The import toClassifier 0x100b15264 checks/accesses the same ten keys, parses the classRefIDs array with QJsonValue::toInt, and uses QJsonValue::toInt(default zero) for both numOfValidFeatures (0x100b16154) and useCount (0x100b161d0). This differs from UInt64→double export and is NOT established lossless roundtrip for large counts. Missing-key/type handling branches and nested Matrix import must still be interpreted before implementing the full converter. No defaults are invented here.

## Typed property conversion and map failure semantics

`profile-variant-access.txt`, `classifier-metatype.txt` and `profile-metatype-json.txt` verify the actual metatype interface at 0x1031ca5b0: its name pointer 0x102647a78 reads **Cortex::MentalCommands::Classifier**. Do not infer the type from an adjacent LLDB symbol label. Converter 0x100b1c700 copies an exact matching typed value (0x100b1c75c..780). For another type it constructs a default Classifier (0x100b1c79c), invokes QMetaType::convert (0x100b1c7cc), and **ignores conversion's boolean return**. Thus loadClassifier returning true means the source QVariant's metatype was valid; it does not mean conversion succeeded, the classifier was trained, or its shapes are valid. A valid wrong-type property can take a failed/partial conversion route; do not assert it invariably becomes a clean default.

EmoProfile::get 0x10123558c initializes an invalid QVariant, searches the in-memory property map, and copies the found value or that invalid default (0x101235634..648). EmoProfile::set 0x1012357f0 checks a lock map and logs a changed locked key (0x101235858..8a8), but **still writes** through helper 0x1001776a0 at 0x101235988. The helper performs map copy-on-write and existing-value QVariant assignment (0x100177780), or insertion. These methods do not themselves read/write disk. `profile-map-store.txt` captures the insertion helper and a scoped symbol query with no matched save/serialize/load methods; absence is limited to that query.

## Proven profile-to-file path; enqueue success is not durability

1. profileToJsonObject 0x100b16788 iterates EmoProfile::items. Its Classifier branch calls the above QVariant converter at 0x100b16a60, Classifier JSON export at 0x100b16a6c, then inserts the object at 0x100b16a88. Hence the typed property and explicit JSON are connected by a real body, rather than two assumed independent formats. Other branches handle numbers, Matrix, GaussianAlgebra and strings; unsupported types log at 0x100b16b38, and complete unsupported-type policy is not implemented here.
2. TrainingProfileManager::saveProfile 0x10041f040 updates a timestamp, calls profileToJsonObject at 0x10041f25c, places that QJsonObject in TrainingProfileAttributes, then calls CacheProfileManager::updateProfileInCache at 0x10041f284. A nonzero returned error skips the '[API] Profile saved' log (0x10041f28c). The log alone is not a disk durability guarantee.
3. updateProfileInCache 0x1000ed114 compares profile/attribute IDs, copies the attributes into its in-memory cache **before** its database calls (0x1000ed1bc). Database vtable slots +0x1e8 and +0x210 resolve in NoSQLDatabaseWrapper's captured table to saveTrainingProfile 0x101e1e1e0 and saveTrainingProfileAttributes 0x101e21864 (`profile-filestore-save.txt`, 0x103183060/3088). The former gets flags 0,1 at 0x1000ed1d0..1d8; only its zero result permits the latter with flags 0,1,1 at 0x1000ed1f4..200. Errors propagate; no rollback of that earlier memory-cache insertion is shown in this body. Exact metadata database write details remain untraced.
4. NoSQLDatabaseWrapper::saveTrainingProfileAttributes sees the second boolean true on this path, uses QMetaObject::invokeMethodImpl connection-type numeric 2 to enqueue worker 'save' (0x101e218cc), **ignores invocation result and returns zero** (0x101e218d0). The synchronous branch invokes the file store and retries only result 0x3303, for at most six total calls (0x101e218f4..21988). On zero synchronous file result it also schedules follow-up work; that tail is not a durability assertion. Third-flag semantics beyond propagation are not inferred.
5. TrainingAttributesWriteWorker::save 0x101e7522c invokes the same store, likewise retries 0x3303 up to six total calls, and emits saveDone with its final code at 0x101e75304. Therefore asynchronous write failure is a later observable completion, separate from the manager's immediate zero return.
6. TrainingAttributesStore::save(profileID,QJsonObject) 0x101e732f8 calls the three-argument save at 0x101e73328 and returns on a nonzero result; subsequent successful-path inspection/logging of training properties is not another serializer. The three-argument save 0x101e73868 constructs QJsonDocument, calls toJson with numeric format 1 (0x101e738a8), calls FileCompress::eCompress (0x101e738c0), encrypts (LocalFileStore::encrypt, 0x101e738dc), then calls LocalFileStore::saveFile only on true encryption result (0x101e738e0..8f4). Encryption false logs and returns 0x3304 (0x101e73998); missing initialized store member at +18 follows an exceptional helper 0x10249ed74, not ordinary success. File result 0..7 maps through the captured table at 0x102fc9f14 to [0,0x3000,0x3301,0x3303,0x3309,0x3300,0x3302,0x3304]; results outside that range become 0x3300. Names/meaning of those numeric error codes require enum evidence.

This proves an actual **typed property → JSON bytes → compression → encryption → file-save** call chain. It does not yet recover compression framing, encryption/key derivation, directory naming, atomicity/fsync, or the inverse load path. No file was decrypted, profile values accessed or vendor assets copied in this continuation.

## Remaining dependencies / deliberate nonimplementation

- Follow FileCompress::eCompress 0x101e72560, LocalFileStore::encrypt 0x101e7fbe0 and saveFile 0x101e7fc7c; capture inverse read/decrypt/decompress and profileFromJsonObject. Respect local comparison-only asset scope: ask the parent/user if actual vendor asset values become needed; no bundling.
- Follow saveTrainingProfile metadata persistence 0x101e1e1e0 and completion wiring to distinguish enqueue, write, rollback and durable completion.
- Follow Matrix mapper 0x100b1735c, Matrix::vector, fromArmadilloMatrix/fromArmadilloUVec; establish flattening/conversion rather than guess.
- Interpret toClassifier failure/missing-key branches and nested imports; compare permitted reference outputs. Lossy integer edges remain.
- Independent versioned profile storage should preserve original values and expose failures; do not silently adopt a potentially lossy vendor interchange format.

No ReferenceClassifierPersistence.swift is introduced: a guessed byte codec or typed-envelope stub would overstate evidence. No builds were run. No exact codec, database decryption, end-to-end profile parity or runtime verification is claimed. No proprietary assets are needed for these static contracts; trained matrices and matching outputs remain separate numeric-validation inputs.

Reproduction uses static LLDB with `target create --arch arm64` against the installed CortexService and disassemble/read commands retained in each capture. `armadillo-json-bridge.txt` retains an invalid unquoted signature command after a successful bridge capture; `profile-map-store.txt` retains a no-match query. These unsuccessful queries do not support positive algorithm claims. Some address-range captures include adjacent methods; claims above cite only the specific identified body sites.
