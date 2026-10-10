# Database driver and transaction evidence for independent storage

Pinned CortexService arm64 SHA256 `cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`. M4 read-only static LLDB. No database values, encryption keys, vendor profile/model assets or vendor binaries copied. This continuation adds evidence only; no runtime/storage source edits, builds, commits or pushes.

## Driver lifecycle and document identity

CouchDriver constructor (`0x101d52dc4`) creates its CouchDatabaseNative wrapper (`52dec`). setDatabaseFolder (`52e50`) checks directory existence, calls mkpath if absent (`52ea8`), then computes an absolute path and passes it to native setDatabaseFolder (`52f20`). mkpath's boolean is not directly tested in this body; do not treat this as robust directory validation. A fixed filename is referenced at `52ef0`; its actual value was not read because it is unnecessary to independent storage design.

open (`52fec`) delegates to native openDataBase (`52ff8`) with caller parameters and maps errors. close (`530d0`) delegates to closeDataBase (`530dc`). Numeric maps contain ordinary error branches, unknown `0x3fff`, special `0xffff`→`0x3310`; exact error-name assignments require enum/table mapping and are not guessed here. No fsync or restart recovery occurs in these thin wrappers.

NoSQLDatabase::driver (`0x101de5d68`) takes an internal mutex (`5d98..5db0`), checks its open-state byte (`5dc0..5dc4` when flag false), and identifies QThread::currentThread (`5dc8`) to search its driver map. Closed/unopened state writes code `0x310d` (`5f98..5f9c`) and logs 'Cannot access database before open() or after close()' (`5fdc`). Captured driver body is partial at its later cleanup/open-creation tail; mutex protection is proven for driver lookup, not a whole profile transaction or cross-process filesystem locking.

NoSQLDocument getId (`0x101dfab60`) returns its field+8, getData (`fab68`) returns JSON field+0x20, and setId (`fab70`) directly assigns QString. No identifier generation occurs in these methods. Treat profile IDs as explicit stable identifiers supplied by higher-level objects; do not infer a namespace or hash from the getter.

## Save/get semantics

CouchDriver::saveDoc (`0x101d531c4`) extracts document ID and JSON (`531e4`, `531f0`). Flag true forwards numeric revision at document+0x40, bool true and extra string+0x48 (`531fc..53210`). Flag false forwards numeric revision0, bool false and the same extra string (`53238..5324c`). Both invoke native saveDocument. No local retry or revision mutation is shown in this wrapper.

Native JSON saveDocument (`0x101f016fc`) converts JSON and delegates to its string overload (`017c0`→`01868`). The captured partial string body references c4doc_get, c4doc_put and c4rev_getGeneration. Full conflict policy and remaining save/body encoding branches are not recovered by this partial capture and are external dependencies for exact database parity.

CouchDriver::getDoc (`0x101d532f4`) gets native document plus error (`5331c`) and maps that error before success handling. Success sets requested ID (`5337c`), string revision (`53388..94`), numeric revision (`533c8..cc`), then body through NoSQLDocument::setDataAsString (`533e4`). Its final result is the parsing result, not merely native-document existence. IDs/revisions can already be modified before a malformed JSON body fails; callers must not interpret a partially changed output as success.

setDataAsString (`0x101dfab78`) parses UTF-8 with QJsonDocument.fromJson without a parse-error object (`faba4`), returns `0x3103` for null (`fabe0`) and `0x3104` for a non-object root (`fac20`), and only replaces JSON payload on object success (`fac00..18`). This is stronger than accepting arbitrary valid JSON and weaker than a trained-profile schema validator.

## Batch transaction order and failure

NoSQLDatabase::saveTransactionDoc (`0x101de6d3c`) asks for driver with flag0 (`6d5c`); if available it delegates through vtable+0x68 (`6d74`), otherwise returns driver-lookup error. CouchDriver::saveTransactionDoc (`0x101d53768`) preserves input order while building DocumentKey entries containing ID, JSON, revision and extra string (`537ec..53834`), then invokes native saveTransactionDocs (`53878`). No extra disk-attribute/cache transaction is attached here.

Native saveTransactionDocs (`0x101f047e0`) requires a nonnull database handle, constructs transaction guard helper `0x101f04ac8` (`0481c`), then saves each DocumentKey in order (`04848`). The first nonzero per-document code stops iteration (`04850`), logs, and requests guard end(false) (`0493c..40`). Normal/empty success requests guard end(true) (`04944..4c`). Per-document error remains the returned code (`04950`).

Guard constructor stores the database and C4Error pointers, initializes a completed byte to0 (`04af0..afc`), and calls a wrapped c4db_beginTransaction. Callback `04c98..ca0` directly invokes actual `c4db_beginTransaction` (`0x10216199c`). Guard end helper (`04d14`) skips work when error field+4 is nonzero (`04d38..3c`) or completed byte is nonzero (`04d44..48`); otherwise it wraps end with requested bool and, if error remains zero, sets completed1 (`04df8..e08`). Callback `04f08..14` directly invokes actual `c4db_endTransaction` (`0x1021619dc`).

Thus the common end(true) following a successful end(false) is a **guard no-op**, not a second commit after rollback. If error occurred, end also skips; exact c4 API/error wrapper semantics remain relevant. Exceptional destructor helper `0x101f024dc` calls guard end(true), which uses the same skip rules; do not silently recharacterize that as unconditional exception rollback.

Important limit: outer native saveTransactionDocs returns its saved per-document code, not the C4Error used by transaction begin/end. The captured body does not directly replace zero with begin/commit error. It also does not visibly check constructor's error before entering the save loop. This is evidence of incomplete explicit begin/commit error propagation in the inspected wrapper, **not proof that commits always succeed or that partial changes occur**; actual c4 library transaction behavior must be tested rather than guessed.

## Consequences for independent storage

- Preserve one explicit stable ID, validated object payload and revision/version contract. Separate payload parsing failure from successful retrieval; publish loaded values only after validation.
- Use a real atomic backend transaction for related independent metadata/profile data where practical, with ordered writes, stop-on-first-error, explicit rollback and begin/commit errors propagated. These are independent reliability requirements; matching the vendor's omitted error propagation is undesirable.
- Attribute encrypted file save, metadata database save and in-memory cache update were already proven separate operations in the profile IO continuation. The document batch transaction does not establish atomicity across those stores. Prefer a single-store independent format or an explicitly recoverable protocol if multiple files are necessary.
- Database driver-map mutex/QLockFile attribute lock are different scopes. Qualify actual backend concurrency and crash/restart behavior; do not infer thread or cross-process safety from a symbol name.
- No crash recovery, WAL configuration, journaling mode, fsync guarantees, restart test or cross-process lock implementation is proven by these wrapper bodies. Those lie in actual c4/LiteCore and OS implementation plus runtime qualification. No production-durability claim is made.

## Remaining concrete gates

Full native saveDocument/getDocument/open/close and NoSQL driver cleanup bodies; exact error-table mapping; c4/LiteCore begin/end, lock and persistence guarantees; restart/crash failure injection; revision conflict tests. No independent code added because root owns real storage and the useful output here is architecture evidence, not another fake database facade.
