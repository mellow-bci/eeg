# Native database document and lifecycle continuation

Status: understood wrapper behavior from static arm64 function bodies; no runtime database fault experiment or vendor asset needed. This adds evidence only. It does not establish the persistence algorithm inside Couchbase Lite Core, exact crash durability, or successful trained-profile round trips.

Binary: M4 installed `/Applications/EmotivApps/EMOTIV Launcher.app/Contents/MacOS/CortexService`, pinned SHA-256 `cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`. Addresses are unslid image virtual addresses. LLDB target creation/disassembly and bounded static vtable/jump-table reads did not launch the process. No database contents, encryption keys, credentials, trained matrices or vendor model assets were read/copied.

## Evidence scope

- `native-bodies.txt`: complete string saveDocument body 0x101f01868–023ec; strToBody 023ec–024dc; getDocument 00cc4–01224 and wrapper helpers; openDataBase 101eff9ac and its cleanup; error map 101f00374–00660; closeDataBase 00660–00880.
- `read-open-thunks.txt`: native JSON save overload 016fc–01868 and resolved open/read callables.
- `write-thunks.txt`: c4doc_create/put/update callables with explicit argument registers.
- `static-tables.txt`: seven non-secret error-map bytes and three callable vtables only. These are static program tables, not profile/database assets.
- Transaction guard bodies and native batch behavior are in sibling `database-driver-continuation-20261011`; cross-reference those captures rather than assuming single and batch save have identical completion behavior.

## Read contract

getDocument converts ID via QString UTF-8 and std::string then uses strlen (00d6c). The actual read callable 05358 loads database +8 and calls c4doc_get with argument w3=1 at 05368. The top-level bool does **not** change that must-exist argument: it controls whether native error code 7 takes the direct return versus warning/map path (00e70–00e98). All other positive errors use errorFromCouchbaseLiteCore. Success sets caller error zero and constructs the shared native-document wrapper at 00eb8. A null database handle goes to exceptional handling (00cf8→010d0), not a successful empty document. Embedded-NUL ID behavior is not generalized beyond the observed strlen call.

## Write and revision contract

The string overload first calls c4doc_get with w3=0 (callable 0544c–05460). A positive initial read error is mapped and returned before starting the transaction. Otherwise it starts the existing guard, encodes JSON, and examines selected revision at document +0x18 (01af0).

| Condition | Actual selected write path |
|---|---|
| No selected revision | c4doc_create, callable 05544–0555c, numeric flags argument 4 |
| Existing revision; top-level bool false | c4doc_update, callable 05718–05728, numeric flags argument 4 |
| Existing revision; bool true; c4rev_getGeneration equals requested UInt32 | c4doc_put, callable 05630–05644; request assembled with selected revision history, null common-ancestor output |
| Existing revision; bool true; generation mismatch | Explicit conflict log; return native code 8 (01d94–01ed0) |

This is a numeric generation comparison, not proof of a full revision-token comparison. Request-layout names beyond the named C4 functions remain dependent on the exact library ABI; do not copy an assumed newer struct definition. The bool false path still delegates race/conflict decisions to c4doc_update; it is not proof of safe unconditional overwrite.

strToBody (023ec) calls c4db_encodeJSON, supplying a local zeroed C4Error, then returns the result slice **without testing or propagating that local error** (02468–024ac). Subsequent write errors determine the observed top-level return. This does not establish a particular malformed-JSON outcome; it requires an executable library/reference experiment.

Common write completion releases the encoded buffer and calls transaction end(true) before inspecting errors (01eec–01efc). Raw write error codes 4 or 8 become native return 8 (01f08–01f18); raw code 16 becomes native return 16; other positive codes use the domain map. These early write-error returns take precedence over transaction errors. If the write error is nonpositive, it then checks the transaction guard C4Error and maps it when positive (01ff8–02008). Only after both checks does it return zero. Explicit generation mismatch also calls end(true) before return 8, but does not pass through that transaction-error check.

**Single-document save therefore propagates a final transaction error when the write itself had no error. Native batch save instead returns its per-document status without independently returning the final guard error.** See sibling transaction trace. No new retry loop, fsync, atomic-rename or recovery implementation is present in these wrappers. Success logging at 02010–020ac is not an additional persistence stage; register reuse across write paths prevents assigning every logged string an unqualified semantic role in this trace.

## Exact numeric error-domain map

errorFromCouchbaseLiteCore first treats nonpositive error code as success zero. For a positive code it subtracts one from domain and dispatches using seven bytes `[0,5,10,7,3,3,9]` at 0x102fd25b8, jump base 0x101f00580, byte multiplied by four.

| Numeric C4 domain | Native return |
|---|---|
| 1 | Original code if <33; otherwise 65535 |
| 2 | 35 |
| 3 | 33 |
| 4 | 34 |
| 5 | 65535 |
| 6 | 65535 |
| 7 | 36 |
| Outside 1…7 | 65535 |

This table reports numeric behavior proven in the installed image. Source enum names and compatibility across other library builds are not claimed. Positive errors are logged with c4error_getMessage. Wrapper-specific save special cases above can bypass this general map.

## Lifecycle and concurrency boundaries

openDataBase selects kC4SQLiteStorageEngine and numeric flags 16 or 17 from its bool (ff9e8–ffa14). Empty encryption-key input chooses algorithm 0; a 32-byte input is copied with algorithm 1; other nonzero lengths enter a helper and return 22 on the ordinary return path (ffd94–ffd98). No actual key was obtained. Exact helper exception behavior is not inferred.

Before opening, an existing handle is cleared from self +8, closed and released (ffae8–ffb0c). There is one ordinary c4db_open call via callable 050d0–050e0, not a retry loop. An open error is mapped at ffd34–ffd3c. Failure leaves the old handle removed; success replaces self +8 with the returned handle (ffd4c–ffd7c). No wrapper mechanism retains the old usable connection if reopening fails.

closeDataBase returns native 6 when handle already null (00728). For nonnull it first invokes wrapped c4db_close, then clears self +8, invokes c4db_close again and releases the handle (00744–00768). Its return depends on the **first** error field; the second close error is not propagated. This establishes cleanup order, not that both library closes must succeed or that close failure preserves data/handle ownership.

These native bodies do not acquire a mutex around document read-modify-write. Higher layers have separate driver-selection mutex/thread bookkeeping and profile lock files (sibling driver/file-lock evidence). C4 transactions and C4 document APIs remain the concurrency authority underneath these calls. Exact isolation, interprocess conflicts, nested transaction behavior, journaling/checkpointing, restart recovery and storage limits cannot be derived merely from the wrappers or SQLite-engine name.

## Independent storage implications and remaining gates

Our storage should explicitly test and report write, transaction-commit and close failures; preserve typed conflict errors; make thread/lock ownership explicit; and verify rollback/restart using our own backend. These are independent design/validation requirements, not a claim that Cortex implements a stronger durability guarantee. Do not replicate ignored encoding/secondary-close errors just to mimic a wrapper.

Remaining reference gates: exact linked C4 version/configuration/ABI; complete C4-level revision race handling and transaction/nesting exceptions; malformed JSON reference outputs; concurrent writers; open/close failure fault injections; actual power-loss/restart persistence behavior. Reference trained-profile assets are neither required nor requested for this static lifecycle trace. No production-parity claim follows from these captures.
