# Private data, provenance and Git LFS

This repository intentionally includes the complete relevant EEG work state at the owner's explicit request. It contains personal electrophysiological recordings, device identifiers, recording metadata and recovered local reference files. It must remain **private** under autonomy-cloud, with access limited by the organization as appropriate.

## Included

- All files from the acquisition work directory, except disposable Python bytecode caches.
- Original encrypted BLE payloads, decoded JSONL, metadata probes, cue markers and analyses.
- Original copied encrypted Parquet snapshots, recovered tables and TEST24 CSV.
- Current/historical source, reports, operation notes and static protocol-analysis traces.
- Hash inventory so archive completeness and accidental modification can be checked.

## Excluded

Account passwords/tokens, SSH keys, unrelated system files, installed vendor executable bundles, Python virtual environments and operating-system caches. No vendor application binary was present in the copied EEG artifact directory. The reconstructed reader and static disassembly traces are included as research provenance; no claim is made that the vendor implementation was authored here.

Large recording formats use Git LFS. LFS is storage, not access control or encryption. Private GitHub access controls apply; people authorized to clone can obtain the data. Do not publish sample records in a public issue or change repository visibility without reviewing the data.

## Reproduction and archival policy

`archive/current-state/` is the preserved source work state. Do not edit it to make tests pass. Maintain current implementations at repository root; document subsequent corrections and retain original evidence. New captures go to ignored `recordings/` until intentionally reviewed for inclusion.

`evidence/archive-manifest.json` records path, size and SHA-256 of every archived file. `evidence/provenance.json` identifies the original copied implementations and key datasets. Sanitized numerical comparison summaries at `evidence/` are conveniences; full original reports remain in the private archive.

A credential-pattern scan is a useful check, not a guarantee that no sensitive data exists: sensitive EEG data is intentionally present.
