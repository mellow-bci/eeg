# Independent real storage qualification

Static reference bodies are captured separately in metadata-schema-continuation-20261011 and database-driver-continuation-20261011. Their pinned arm64 CortexService SHA256 is cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a.

Root owns ReferenceLocalProfileStore and tests. Full typed classifier is derived from ReferenceClassifierRebuild.fit using independent synthetic class distributions, not copied vendor parameters. This checkpoint uses no headset or participant input. No vendor salt, keys, profiles, binary or trained model is embedded. No UI/other-project changes belong to this checkpoint.

Three scoped steps: (1) trace all ten metadata field names and typed bounded handling; (2) connect actual fitted classifier, metadata and caller runtime settings to independent authenticated SQLite storage; (3) test reopen, conflicting revisions, real database contention, fault boundaries and actual killed uncommitted SQLite writer recovery.

SQLite runtime/CLI on qualification host: 3.54.0. Tests use a private temporary directory, database permissions0600, WAL, synchronousFULL, supplied32-byte synthetic key and AESGCM randomized nonce. Realpath resolution was required because the macOS Foundation temporary-directory URL retains /var whereas SQLite NOFOLLOW rejects ancestor symlinks. Database file symlinks remain rejected; this is tested.

Initial targeted run failed with SQLITE_CANTOPEN from /var alias; corrected by POSIX realpath of parent. Targeted final run passes10tests. Final reference/core runs and source hashes are recorded alongside this note. Those failures are not hidden as success; successful logs correspond to subsequent corrected implementation.

The real interrupted-write test executes /usr/bin/sqlite3, waits until a transaction has staged replacement revision/payload, sends SIGKILL, and confirms the previous authentic classifier restores with executable inference. Beforecommit throw tests and aftercommit acknowledgement fault tests distinguish rollback from committed-but-unacknowledged state. This is process termination/reopen qualification, not a disk power cut or actual hardware durability test.

Remaining: complete Qt date/channel coercions, vendor native database format/error/conflict internals, external trusted rollback detection, app keychain management, physical storage/diskfull qualification, and trained Cortex profile/reference-output and prospective physiological validation. Independent format is explicitly not vendor Couchbase/file compatibility.
