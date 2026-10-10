# Database save orchestration continuation

Pinned installed CortexService arm64 SHA256 cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a reverified via SSH shasum. Static LLDB function bodies only; no vendor profile values, embedded salt, credentials, model assets or runtime changes. Captures retain commands and instruction addresses.

## Cache and wrapper order

Prior updateProfileInCache body0x1000ed114 publishes attributes before saveTrainingProfile(+1e8 vtable) then saveTrainingProfileAttributes(+210); metadata errors skip attribute save, but no cache rollback occurs. This continuation composes that order with mandatory callbacks; unequal IDs are explicitly outside the supported normal domain. The previously captured cache body is referenced in the manifest.

NoSQLDatabaseWrapper::saveTrainingProfile0x101e1e1e0 forwards via concrete helper1e1e1e4. It converts TrainingProfile::toJsonObject at1e1e510, creates NoSQLDocument at520, calls underlying NoSQLDatabase::saveDoc at598 and preserves its result. Only success plus nonnull updater and third flag trigger MetaDocumentUpdater::addChanges at5c0. Wrapper saveDoc0x101e17fe8 has the same conditional at18010..034, forwarding the second flag to the database. Attribute metadata helper101d167cc constructs TrainingProfileAttributesInternal JSON and calls wrapper saveDoc at16b9c, forwarding its two flags unchanged. TrainingProfileAttributesInternal::toJsonObject101fadc94 creates only uuid from member+8; it does not serialize classifier attributes into the metadata document. Full TrainingProfile metadata JSON fields and Couchbase driver semantics remain separate from this scoped control flow.

## Synchronous versus queued attribute save

NoSQLDatabaseWrapper::saveTrainingProfileAttributes101e21864 takes an exceptional branch on first flag nonzero (21880→21a28); only first=false is implemented. Second flag true queues worker save with connectiontype2 at218cc and ignores invocation bool before returning0 at218d0. Our result retains the callback invocation bool diagnostically alongside vendor-reported0. It never calls failed enqueue durable success.

Second flag false writes TrainingAttributesStore::save, retries only0x3303 up to6 total calls218f4..21988. On zero it builds UUID-only internal metadata then invokes helper101d167cc directly at219ec, with first=false and forwarded third flag; its returned error becomes final result. This is a synchronous metadata write, correcting the previous capture's tentative scheduling description. File failure skips that phase. Queued completion uses the separately traced worker/saveDone path from profile-io-orchestration-20261011. No cross-file/database transaction, rollback or fsync is inferred.

## Underlying document retry and change notification

NoSQLDatabase::saveDoc101de6664 acquires driver(error*,false) atde668c. Absent driver returns supplied error with no write. Present driver calls vtable+38 with document and forwarded bool atde66b8. Only numeric0x3102 retries. After each such result it sleeps5ms atde66d0, even on the last exhausted call; old counter compares against9 atde66dc before increment, giving10 total calls and10 sleeps on full exhaustion. Other results return immediately. Error-enum meaning is not guessed; driver internals and physical DB qualification remain explicit dependencies.

MetaDocumentUpdater::addChanges101dd225c protects insertion with QBasicMutex atdd2278..22d8, then queues onDatabaseUpdated via invokeMethod(connectiontype2) atdd2338. Our wrapper supplies notification explicitly; it does not reproduce Qt queue scheduling, deduplication, thread safety or a cloud-sync guarantee.

ReferenceDatabaseOrchestration adds driver-error propagation, bounded numeric retry, success/flag/updater notification gates, cache publication order, queued versus synchronous attribute-save outcomes and UUID-only metadata. Nine authored tests pass in the19-test combined database/file/profile-lock focused run. Final full checkpoint reproduction is coordinated by root. No vendor assets needed for these contracts.

Final consolidated verification: focused Reference|Decoder235executed,233passed,2absent-reference-fixture skips,0failures; full EEGCoreTests427executed,423passed,4explicit skips,0failures. Both commands, complete output and failure/skip counts are retained in focused-tests.log/core-tests.log. The fitted→serialized→inverse→runtime test uses our own values and key/IV, not Cortex trained assets. No physical headset trial or trained vendor runtime comparison occurred.
