# ErrorSetClassifierBank comparison contract

Reference arm64 CortexService SHA256 cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a. Static LLDB bodies only; no trained assets, database or vendor executable bundled.

## Key / ownership

keyGen 0x100b3fc38 calls the existing ordered signed-int formatter 0x100b260fc with comma delimiter, appends the C string at 0x103088af4 (memory read verifies ':' then NUL), and appends ordered unsigned-long values from helper 0x100b3fe34. That helper uses unsigned-long ostream insertion at 0x100b3ff04, inserting commas only between values at 0x100b3ff14..f3c. No sorting or deduplication. Empty vectors yield ':'.

get 0x100b4000c returns null on missing key (0x100b400b0), otherwise copies QSharedPointer (0x100b4004c..6c), checks nonnull and verifies payload classifier actions via equal vector byte-length and memcmp (0x100b40074..90). No usage increment occurs within get. put 0x100b400ec rejects null at 0x100b40104 but does not perform get's action assertion; it stores the supplied shared classifier, not a classifier copy. ReferenceErrorSetCache.Entry is therefore a reference type; callers can explicitly mutate reuseCount/payload and observe the same identity. This does not recreate Qt ownership, locking or serialization.

## Capacity / invalidation

Constructor 0x100b3fbb4 sets capacity +0 and map count +18 to zero. No enabled member or gate exists in these bank bodies. The manager's enable-error-set policy is external and must not be confused with this bank's zero capacity (uncapped).

setMaximumNumOfClassifiers 0x100b3fbc8 assigns +0 and clears the map every call, even unchanged or zero. clear 0x100b3fc00 clears entries without changing capacity.

put existing-key path 0x100b40128..160 replaces directly, before capacity logic. New-key path checks nonzero limit at 0x100b40188..198. At capacity it iterates ordered map nodes and compares classifier+460 unsigned usage values (0x100b40208..21c); candidate changes only on strictly lower usage. Thus minimum usage wins; equal usage preserves first lexical key. It removes exactly one then inserts. It is not an LRU cache. `get` itself does not change frequency. The separate storageLimit in our comparison helper is an explicit independent memory guard, not recovered vendor capacity; rejection leaves contents intact.

## Manager sequence boundary

manager-call-order.txt is an excerpt of ../deployed-feature-continuation-20261011/manager-path.txt. runDetection obtains current ordered class IDs at 0x100b32690, looks up bank manager+af0 using those and supplied channel vector at 0x100b326a8. Cache hit is classified at 0x100b32714, then shared classifier+460 increments with wrapping UInt64 add at 0x100b3271c..724; missing cache falls through the manager-owned temporary-mask/refitting path. New fit invokes buildClassifier(false) at 0x100b32980; only success reaches bank put at 0x100b329f8. Root owns that mask/refit interpretation; this helper does not fabricate missing classifiers.

Additional known invalidations (cross-references): manager init assigns configured limit/clears at ../neutral-training-continuation-20261010/init-buffer-reset.txt 0x100b37f7c; accepted training clears at ../training-lifecycle-continuation-20261011/lifecycle-bodies.txt 0x100b33634; loading profile clears at 0x100b320a0. No cloud/database persistence contract follows from these cache bodies.

## Validation / scope

Five analytic tests cover ordered actions/channels/duplicates/UInt64 bounds, empty key, shared identity and nonmutating get, minimum-frequency lexical-tie eviction, replacement, same-value limit reset, explicit storage guard, null put and get-time action mismatch. Command: `swift test --package-path apple --filter ReferenceErrorSetCacheTests`.

No matching Cortex runtime test fixture is available; function-body correspondence and analytic tests are not an end-to-end parity claim. No vendor model assets are needed for this cache primitive.
