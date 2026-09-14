# Local reference recording recovery

## What happened

The official app recorded TEST24, but PRO-LITE blocked its export UI. The work
recovered a **copy of locally saved data** independently. The app was not patched,
the export entitlement was not changed, and no vendor process was attached to or
modified for the key reconstruction.

TEST24's official app log supplied its title, record ID, device-session ID and
start/end timestamps. The matching device-session `.eparquet` file was found in:

```text
/Library/Application Support/Emotiv/Cortex/v2/database/parquetStore/
```

The original file stayed unchanged. The complete copied inputs, recovered output,
CSV, scripts and reports are retained at `archive/current-state/reference-test24/`.
They include private identity/timing metadata intentionally in this private repo.

## Key retrieval and authenticated decryption

`tools/read_record.cpp` reconstructs the observed Cortex V1 file-key retriever.
Parquet key metadata must contain exactly `1:<part2>:<part3>`. It rejects other
versions or extra separators. The key is:

```text
SHA256(ASCII("emotiv_jan2019") || part2 || part3)
```

There are no inserted separators between these three concatenated byte strings.
The fixed prefix is a protocol namespace discovered in the installed binary.
Derived keys remain in memory and are not printed.

The helper passes this retriever into Apache Parquet's `FileDecryptionProperties`,
opens read-only, reads the table, validates it, and writes a **new** Parquet file.
It refuses an existing destination. `--eeg-only` selects Timestamp,
OriginalTimestamp, EEG.* and CQ.* columns; default behavior retains all columns.
The input footer signature/magic is PARE, and standard Parquet authenticated
reading validates the encrypted data it reads.

Unlike the BLE ECB framing checks, this file-level authenticated read can detect
tampering. A disposable copy was changed at byte `[-20]`; reading failed with
`Failed decryption finalization` and produced no output. This supports successful
file recovery, not a claim that all later interpretation is correct.

## Active device-session snapshots

An active recording had a separate `.footer` sidecar. For the fresh retest:

1. Read sidecar footer A.
2. Copy the current data file bytes.
3. Read sidecar footer B and require A == B; otherwise retry.
4. Concatenate copied data with A into a new private snapshot.
5. Record byte sizes, source identity, method and SHA-256.
6. Transfer, verify SHA-256, then require authenticated Parquet reading to succeed.

This is not a filesystem-level atomic snapshot. It relies on the observed
append-only data/sidecar behavior, stable copied footer and successful authenticated
read of referenced row groups. A changed vendor storage implementation requires
revalidation. The first older paired snapshot did not have the A/B check; its
method and limitation are retained in its original provenance report.

## Interval extraction

Use the logged start/end interval against **Timestamp**, inclusive, not silently
against OriginalTimestamp. TEST24 recovered 14,109 rows from 22,424 source rows,
with zero interpolation and no counter discontinuities. These boundaries are
log-derived; an official exporter could choose edge rows differently.

The generalized extractor takes input path, timezone-qualified start/end times,
headset identifier and new CSV output. It labels the result local recovery,
`official export:false`. `reference_csv.py` validates shape, numeric fields,
strictly increasing timestamps, modulo counters, interpolation and CQ ranges.
It cannot establish same-acquisition identity itself.

## Build and use

```sh
.venv/bin/python -m pip install -r requirements-reference.txt
.venv/bin/python tools/build_reader.py --output build/read_record
build/read_record INPUT.eparquet NEW-OUTPUT.parquet --eeg-only
```

The helper currently uses macOS CommonCrypto and pyarrow-provided libraries;
macOS/Xcode tooling is required. This offline tool is not a dependency of live
acquisition. Vendor executable bundles are not included; only our reconstruction,
static research traces and data copies are archived.
