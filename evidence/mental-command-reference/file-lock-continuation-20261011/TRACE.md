# FileLocker lifecycle and attribute file callers

Pinned M4 installed CortexService arm64 SHA256 `cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`; read-only static LLDB. No proprietary data, profile values, vendor salts, keys, binaries or model assets included. No licensing/firmware modifications.

## Actual constructor, state check and destruction

`FileLocker::FileLocker` (`0x101e7e31c`; constructor alias `0x101e7e5e8`) invokes QLockFile's constructor with the supplied path (`7e344`). It forwards its supplied integer timeout unchanged to exactly one `QLockFile::tryLock(int)` (`7e3c8..7e3d0`). True skips diagnostics to return. False calls `getLockInfo` (`7e3f8`), logs filename/process/host/application and `QLockFile::error()` (`7e4dc`), then returns. No retry, forced lock removal or stale-lock override is present in this wrapper.

`isLocked` (`0x101e7e5ec`) directly tail-calls QLockFile::isLocked. It does not use a cached tryLock result.

Destructor (`0x101e7e5f0`; alias `0x101e7e674`) calls `QLockFile::unlock` unconditionally (`7e604`), logs, then destroys QLockFile (`7e65c`). It does not first check acquired state. Constructor-exception cleanup also destroys its QLockFile (`7e5dc`), but no ownership is asserted before underlying construction completes.

## File-store callers

LocalFileStore::saveFile appends literal `.lock` to the derived data filename (`0x101e7fd98..fda8`), constructs FileLocker with timeout integer **1000** (`7fdb4..db8`), then independently calls isLocked (`7fdec`). A false check destroys the locker and returns raw file result **3** (`7fe30..fe3c`); it does not open/write the data file. On true it opens QFile mode numeric10 (`7fe08`), writes (`7fe18`) and closes (`7fe24`); negative write result takes an error path. Short-positive-write handling/durability is outside this continuation.

LocalFileStore::readFile likewise appends `.lock` (`7f784..794`), passes1000 (`7f7a0..a4`), checks isLocked (`7f7d8`), and calls readData only when locked (`7f7e8`). It releases the locker after reading (`7f7f8`) or through error cleanup. Existing inverse-file capture includes the unavailable-lock branch at `7f88c`/cleanup `7f894`. The enclosing TrainingAttributesStore maps raw file result3 to `0x3303`, explaining the higher worker's traced six-call retry rule; exact codec/error map is the disk-codec continuation's contract.

TrainingAttributesStore::save/get call these LocalFileStore routines; they do not acquire an additional independent lock around the complete compress/encrypt/write or read/decrypt/uncompress pipeline. This is a file IO critical section, not evidence of a transactional profile/cache/database boundary.

## Bounded independent contract

`ReferenceFileLock` is explicitly a lifecycle reference, **not an OS lock implementation**. Callbacks supply tryLock, diagnostics, actual isLocked, unlock, disposal and the data operation. One try is made; failed acquisition runs diagnostics; the data operation depends on separately observed lock state; cleanup unlocks then disposes even on unavailable lock or a thrown data error. `.lock` suffix helper is explicit; path derivation is left to the independent storage implementation.

Nonnegative Int32 timeout is our support policy to avoid a potentially indefinite negative wait; the vendor wrapper simply forwards int and the inspected callers pass1000. No sleeping, arbitrary retries, fake acquired state, stale-lock deletion or fsync claim is introduced. Exceptions thrown by independently supplied operations retain their identity while defer releases the lock; backend callback correctness remains a dependency.

Five tests verify operation order and path suffix, unavailable-lock operation suppression with cleanup, separately observed isLocked rather than tryLock return, cleanup/error propagation, and negative-timeout rejection without touching callbacks. These are analytic callback contract tests, not filesystem contention/durability tests. No package build was run by this agent; files are frozen for the parent's coordinated run. `git diff --check` passed.

## Remaining qualification

- QLockFile's platform lock-file creation, process liveness/stale lock timing, unlink safety and cross-host behavior are delegated library internals, not recovered by this wrapper.
- An independent real OS locking backend must be implemented/qualified against concurrent readers/writers, crashes, permissions, contention timeouts and leftover files before production claims.
- File close/write success does not establish atomic rename, fsync or restart durability; exact short-write behavior remains in the file-store continuation.
- Different process-level error naming cannot be assigned from raw numeric3 alone beyond the observed unavailable-lock branch and mapped retry code.
