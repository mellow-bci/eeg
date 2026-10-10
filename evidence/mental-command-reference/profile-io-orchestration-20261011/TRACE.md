# Profile IO orchestration: bounded callback contract

Pinned CortexService arm64 SHA256 `cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`. Read-only static M4 LLDB capture. No profile values, keys, model assets, firmware changes, runtime execution, storage emulation or vendor binaries included.

## Inverse disk load and cache insertion

`CacheProfileManager::getProfileAttributesFromCache` (`0x1000ecc80`) takes a recursive mutex and calls `findProfileAttInCacheByProfileId` (`eccc4`). Only zero error copies returned attributes into output (`eccd4..eccf0`); it returns the recorded code after unlock. The find helper (`0x1000ecd28`) returns the existing map item on a cache hit (`ecda4`). A miss calls database vtable+0x1f0 for metadata (`ecdc8`), returns immediately on error (`ecdd0..dd8`), then calls +0x218 for attributes (`ece18`). Only zero results lead to a copied new attributes value and map insertion (`ece2c..ece84`). Exact map helper and concurrency implementation are outside the callback reference; a cache miss cannot be interpreted as an empty successful profile.

`NoSQLDatabaseWrapper::getTrainingProfileAttributes` (`0x101e21a48`) directly calls `TrainingAttributesStore::get` at `21a68`; it assigns the requested profile ID to output even on a nonzero result (`21a70..78`) and returns the original code. No read worker/enqueue/retry is shown here: this inspected path is synchronous. Do not invent a NoSQL loadAttributes worker based on write-worker symbols.

Store inverse normal path is `readFile` (`0x101e73af4`) → `decrypt` (`73b38`, false branches to error) → `eUncompress` (`73b4c`, empty output branches to error) → `QJsonDocument::fromJson` (`73b6c`, parse error checked at `73b74`). This capture is deliberately partial; exact byte framing, numeric error table, object-root policy and codec are owned by the separate disk-codec continuation, not reconstructed here.

`TrainingProfileManager::loadProfile` (`0x10041f5a0`) first resolves the name to ID (`41f5f0`) and checks manager/device load state; observed gates return numeric `0x2006`, `0x6001`, `0x6006` but their enum meaning is not guessed. New-load path gets metadata (`41f70c`), checks device compatibility (`41f724`), gets cached-or-disk attributes (`41f748`), and short-circuits on each nonzero error. Only then calls `jsonObjectToProfile` (`41f76c`). It sets the loaded flag (`41f7b8`), installs device-map state (`41f7ec`), and emits profileLoaded (`41f838`). Exact JSON branch acceptance and loaded-device reuse path remain separate contracts; this sequence alone proves no trained model correctness.

## Save completion is two phases

`willSaveTrainingAttributesAsync` (`0x101e17acc`) initializes the worker with its store, creates a thread, moves the worker to it, and explicitly connects worker saveDone to `onSaveTrainingAttributesDone` (`17b2c..17b8c`, connection type 0/AutoConnection); it starts the thread (`17c0c`). This establishes an actual completion consumer, not just an unused signal.

Worker `save` (`0x101e7522c`) makes one store.save call; only result `0x3303` triggers the next call. There are at most six total unrolled calls (`75254,75274,75290,752ac,752c8,752e8`); it emits the final code exactly once by tail call to saveDone (`75304`). No delay/backoff is shown.

`onSaveTrainingAttributesDone` (`0x101e17c38`) emits the database-level completion directly for a nonzero write code (`17c58..68`). On zero, it creates an internal attributes object containing the ID and calls helper `0x101d167cc` with flags 0,1 (`17cb0..b8`), then propagates that helper's result through the same completion signal. The helper's tail calls `TrainingProfileAttributesInternal::toJsonObject` (`16b10`), builds a NoSQLDocument (`16b20`), and calls `NoSQLDatabaseWrapper::saveDoc` (`16b9c`). Thus successful file-save completion is followed by a metadata/document save whose failure can replace zero. Exact metadata flags/update fields and saveDoc durability remain untraced; no atomic cross-file/database transaction or fsync guarantee is inferred. Prior cache update remains before disk save and no rollback was established.

## Independent reference implementation

`ReferenceProfileIO` supplies explicit callbacks for cache lookup → metadata check → attributes read → cache insert, the six-call numeric retry rule, and write-code/downstream-code completion propagation. It stores no data itself and does not report enqueue as a durable success. No vendor keys or codec are required for these control-flow pieces. Mutex, queue/thread scheduling, actual storage, profile JSON conversion, loaded-device state and database side effects are intentionally outside this bounded contract.

Six callback-contract tests cover cache-hit storage avoidance, miss order, errors blocking insertion, retry-only-0x3303, six-call exhaustion, and second-phase completion errors. These validate control flow with explicit callback observations, not actual disk writes or Cortex runtime comparison. No build was run by this agent; tests await the parent's coordinated run. `git diff --check` passed.

## Remaining concrete gates

- Trace `saveDoc` and the internal-attributes body fields to establish metadata update and persistence semantics; the completion callback deliberately does not fake them.
- Full inverse store codec/error table/object-root parsing is in the separate codec work; encryption assets remain local-comparison-only and absent here.
- Trace load reuse/conflict branches, exact compatibility policies and loaded-state rollback on exceptional paths before implementing the complete manager.
- Integrate actual independent filesystem storage and observe errors/restarts before claiming end-to-end durability or production-ready profile persistence.
