# Local profile inspection and serialization trace — 2026-10-10

User authorized local profile inspection for comparison. No trained profile data was obtained or copied into this repository.

## Observed storage access

M4 Cortex database location: `/Library/Application Support/Emotiv/Cortex/v2/database/couchDb.cblite2`. Directory is root-owned, mode0700. SSH traversal returns Permission denied; `sudo -n` requires a password. No permissions were altered. This prevents direct inspection through the current remote session. Merely finding the database does not establish that a trained mental-command profile exists inside it.

Other discovered detections include encrypted TFLite files named for MN8/MW20 attention and cognitive stress. These are not evidence of EPOC X mental-command assets and are not required or used for this work. No contents inspected.

## Loader and serializer bodies

Installed arm64 CortexService SHA256: cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a. Captures were static LLDB disassembly only.

- `Classifier::loadClassifier` 0x100b24d04 clears existing classifier, fetches EmoProfile key `cognitiv-classifier` at0x100b24d68, converts the QVariant to a classifier and transfers fields via helper0x100b24e68. This is a typed aggregate, not loose default values.
- `profileToJsonObject` 0x100b16788 enumerates profile items and dispatches typed values including matrices, GaussianAlgebra and Classifier. Classifier serializer called at0x100b16a6c.
- `toJsonObject(Classifier)` 0x100b14a80 exposes `weightMeanVariances`, `classRefIDs`, `uniqueFeatureIndices`, `coeff`, `pcMeans`, `eigenvec`, `meanTot`, `channelInUse`, `numOfValidFeatures`, `useCount`.
- `toJsonObject(WeightMeanVariances)`0x100b13edc exposes `weight`, `mean`, `variances`. Nested matrix layout and correspondence to covariance/component axes still require tracing; names do not resolve it.
- GaussianAlgebra serializer0x100b135ac exposes `classRefId`, `gaussianData`.

These exact field names provide a comparison export contract candidate, but no importer is implemented until matrix layout, class order and profile values can be verified. A JSON serialization route exists; accessibility via a public API/export path remains unestablished. No tier bypass or vendor asset distribution is implied.

## Next reference-data requirement

A readable local/exported trained mental-command profile plus known inputs and Cortex outputs is needed for matched-parameter numerical comparison. Source files must remain outside tracked deliverables. If no trained profile exists, creating a reference profile requires a separately scheduled, labeled participant experiment. Current static tests alone are insufficient.

## Matrix JSON follow-up

Serializer0x100b11a94 emits `rows`, `cols`, `elements`. It obtains Matrix::vector() at0x100b11be0, converts its elements to QVariant list through helper0x100b1735c, then inserts QJsonArray. Armadillo matrix serializer0x100b11ed4 converts through Cortex::Math::Matrix before this routine. Flat array row/column layout still requires the Matrix vector/storage body: do not reshape using a guessed order. Classifier JSON parser0x100b15264 explicitly reads the same named fields confirmed above.

A read-only existing-file ACL command was supplied for the user to execute on M4. A subsequent SSH check still returned Permission denied; command completion is not assumed. No file ownership or mode was changed by the agent. Matched-profile tests remain pending actual access.

## Access verified and next storage gate

After the user executed the M4 ACL command, remote read/traversal succeeded for db.sqlite3, db.sqlite3-wal and db.sqlite3-shm. Direct read-only SQLite schema query fails with SQLite error26 (file is not a database). File header lacks the standard SQLite signature. This is evidence of a non-plain database, consistent with Cortex's database encryption code; it does not alone prove the exact cipher/key.

Config file db.conf is45bytes with a UUID-shaped value; no contents or identifier emitted. `getDbConfigContent`0x101d6a52c calls QBinaryJson::fromBinaryData then validates an object. `getDatabaseKeyId`0x101d6a8e4 reports a missing keyId on malformed configuration. Therefore the config is a key-ID container, not evidence that the actual encryption key is present in plaintext. No key obtained, no profile exported, no active database altered.

## Matrix axes and median broadcast

Matrix::operator()(row,col)0x102134fa0 addresses row*stored-column-count+col, establishing row-major storage. Matrix::vector()0x102135058 returns the underlying vector object. `toArmadilloMatrix`0x10212cfc4 transposes storage and constructs an Armadillo matrix with ORIGINAL rows and columns, preserving logical axes. Median helper0x100b2240c axis0 branch produces1xcolumnCount values across rows. Broadcast subtract helper0x100b1fd44 requires that shape and subtracts the column value from each row. Independent preprocess implementation now tests odd/even row-count fixtures and invalid input. Actual selected-channel mapping and raw caller window recipe remain unresolved.

Native follow-up command: `swift test --package-path apple --filter 'Reference|DecoderTests'`. Result30executed,1skipped,29passed,0failures. This does not establish executed-Cortex parity.


## Database access and read-only snapshot milestone

The user executed the ACL on **M4**, not M3. Read access is now verified.
The prior permission-denied entries above are historical and superseded.

Static bodies show that `getFixedKey` first hex-decodes an embedded key and
ciphertext, decrypts with AES-256-ECB, converts the result through UTF-8, and
passes it to `wrapKey`. The previous failed probe hashed the hex text directly;
that was not the traced path and is not evidence against fixed-key opening.
The corrected local probe succeeds: AES-256 page decoding produces the exact
SQLite format header; the AES-128 probe does not. Private key material and the
probe remain outside this repository. No licence code or active database was changed.

A stable double-read snapshot of db.sqlite3 and its WAL was decoded privately
on M4. Committed WAL frames were overlaid on page numbers using the traced page
codec. Nonce reserve bytes and the eight clear page-one header bytes were kept
separate from XOR-transformed content. The merged copy is mode 0600 and was
opened with SQLite mode=ro, immutable=1. `PRAGMA quick_check` returned `ok`;
kv_default contains 80 documents. **Full integrity_check did not complete**:
SQLite needs the application-specific `fl_value()` index function. We did not
stub that function or count this as a full index-integrity pass. A follow-up stable snapshot validates the WAL header checksum and rolling
frame checksums before applying 886 committed frames; quick_check again returns
ok. This is still an experimental reference extractor, not a supported
production database exporter.

This confirms readable database structure, not a recovered trained classifier.
The metadata-body Fleece CLI probe could not parse the complete stored bodies;
the revision envelope/shared-key mapping remains to be decoded if needed.
No user/account/licence document contents were exported to this repository.

## Actual profile storage path

- TrainingProfileManager::saveProfile calls profileToJsonObject, constructs
  TrainingProfileAttributes, and passes metadata + attributes to updateProfileInCache.
- NoSQLDatabaseWrapper::getTrainingProfileAttributes at 0x101e21a48 calls
  TrainingAttributesStore::get at 0x101e73ab8.
- The get body calls LocalFileStore::readFile, LocalFileStore::decrypt,
  FileCompress::eUncompress and QJsonDocument::fromJson in that order.
- The write worker calls TrainingAttributesStore::save; suffix declarations
  include .emu2, .emu2.encrypted, .eemu2 and .egemu2.

The directly enumerated M4 database/attStore directory contains **zero entries**.
No files with these suffixes were found in the checked Emotiv support directories,
Documents or Downloads. A missing/unreadable search root is not proof that no
profile exists anywhere on the machine or in the vendor cloud. No trained
mental-command parameter set was recovered. The user selected **continue offline
work for now**, so no new physiological training session was started.

## Feature mapping correction

The captured `BandRatioTxf::returnBandPowerOnly` body reads ordered coordinate
pairs from its stored matrix. Both coordinates are converted to integers;
input storage uses column-major offset column*rows + row. At
0x10212faf4..0x10212fafc the selected power is transformed by log10 and multiplied
by 10. This is a decibel feature, not a linear power feature. Actual coordinate
values, upstream channel order and the deployed mode must still be established.

`ReferenceMentalPipeline` now composes explicit preprocessed windows, Hamming,
FFT, band means, ordered decibel features, supplied learned transforms and full
Gaussian parameters, posterior, per-slot LPF and command/neutral scoring. Its
recipe requires all dimensions, coordinates, parameters and activation settings.
There are no inferred device mappings or default learned values. Zero power
rejects rather than adding an invented epsilon. State is committed only after
successful processing, and reset is explicit. This remains comparison-only;
existing acquisition and production profiles have not been changed.


## Offline training trace continued

Captured full bodies/call sites, not just function-name inventory:

- onTrainingStarted 0x100b330e8 locks training action, autoSamplingNeutral,
  active actions, activation threshold, four action thresholds and rebuildSignature.
- onTrainingWaitingForAcceptReject 0x100b334cc unlocks trainingControl.
- onTrainingAccepted 0x100b33570 calls buildClassifier and saveClassifier;
  a branch clears/saves the classifier and clears the error bank. It also
  updates training counts/signatures/brain-map data and calls completion.
  The precise branch semantics are still under review; do not label this a
  recovered acceptance/rejection algorithm.
- buildClassifier 0x100b2f64c checks class references and classifier-cache paths,
  loads existing class feature/Gaussian data, combines newly collected matrices,
  calls GaussianTraining::addUpdate, persists class data, calls
  GaussianTraining::run, and conditionally caches the resulting classifier.
- GaussianTraining::run 0x100b42b44 calls combineClassGaussian,
  runUnivCoordSelection, buildSignatureFromPCA and extractChannelInUse.
  The coordinate-selection body includes per-class averages, covariances,
  epoch counts, an aggregate transform, sorting and selected-coordinate
  reconstruction. **The selection formula, cutoff and learned-transform
  fitting are not yet recovered or implemented.** The PCA builder is outside
  this capture's completed range.

These captures define the next bounded offline work: derive Gaussian sufficient
statistics merging, coordinate selection, PCA/canonical fitting and the
acceptance/neutral state machine, with analytical fixtures before recipe
integration. There is no new vendor model asset dependency established by
these bodies. Learned participant parameters remain necessary for a genuine
matched-profile Cortex comparison.
