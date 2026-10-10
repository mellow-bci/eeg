# Profile save/load lifecycle body confirmation

Read-only static LLDB inspection of the installed arm64 CortexService on M4, SHA256 cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a. No process attach, vendor profile values or model assets. manager-save.txt captures the complete named saveProfile body; load-and-cache.txt captures the complete named loadProfile body followed by a scoped cache-update range. Instructions after the cache update return are adjacent helper bodies, not part of updateProfileInCache.

## Save

TrainingProfileManager::saveProfile 0x10041f040 acquires a recursive mutex, resolves the profile metadata/current user path, invokes checkCompatibleProfileWithDevice at 0x10041f184, and gates later work on the returned status. The existing compatible-profile save path updates currentDateTime at 0x10041f220, creates attributes, converts EmoProfile to JSON at 0x10041f25c and calls updateProfileInCache at 0x10041f284. Nonzero return skips the saved log. Separate create/not-found and error branches remain distinct, rather than treating any named profile as a successful update.

Cache update 0x1000ed114 compares metadata/attribute identity before insertion. It inserts the attributes into memory at 0x1000ed1bc before database calls. First vtable call +0x1e8 receives flags0,1 (0x1000ed1d0..1d8). Only zero status permits the +0x210 call with flags0,1,1 (0x1000ed1f4..200). Status propagates and no memory-insertion rollback is shown. The previously captured vtable resolves these to saveTrainingProfile/saveTrainingProfileAttributes. See ../persistence-cache-continuation-20261011/TRACE.md for asynchronous worker enqueue versus completion and ../native-database-continuation-20261011/TRACE.md for document commit status. Do not infer durability from the manager's log or immediate return.

## Reload

TrainingProfileManager::loadProfile 0x10041f5a0 resolves name to identity at 0x10041f5f0, loads metadata by ID at 0x10041f70c and rejects nonzero status. It calls device compatibility at 0x10041f724 and rejects nonzero status before reading attributes. getProfileAttributesFromCache at 0x10041f748 has its own nonzero error path. On success the attributes' JSON is converted through jsonObjectToProfile at 0x10041f76c, the resulting profile is assigned, loaded flag is set true at 0x10041f7b8, device association is updated at 0x10041f7ec, and profileLoaded is emitted at 0x10041f838. This is a proven deserialization/association chain, not proof that every imported classifier is numerically valid. Existing inverse/runtime tests cover our explicitly supported schema.

## Independent workflow policy

Our SQLite/AES-GCM profile publication checks actual commit acknowledgment and reload validation. It intentionally does not reproduce Cortex's separate memory/metadata/encrypted-file acknowledgment as an atomic guarantee. Comparison training kernels preserve their traced write-before-fit and cleanup ordering; an independent durable-publication receipt is separate from acceptance/property-save status. Recipe/version/provenance must be checked on reload, and unsupported or absent learned parameters never become a successful model. Restart/inference tests are authored inputs; matched Cortex profile/stage outputs remain required to prove numerical parity.

No new vendor assets are required for these control-flow observations or our independently trained profile. Exact vendor-file encryption compatibility has the previously documented embedded-salt dependency, which is excluded from the deliverable and not needed by our store.

Reproduce static captures with LLDB `target create --arch arm64` for the installed CortexService followed by `disassemble -n` using the two mangled names retained in the capture command headers. Product EEGCore does not launch or link Cortex.
