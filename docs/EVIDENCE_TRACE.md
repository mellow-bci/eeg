# Static evidence trace

Installed CortexService arm64 binary SHA-256:
`cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`.

Addresses are binary-build-specific, not stable public APIs. The full symbol
inventory and targeted static disassembly outputs are retained in
`archive/current-state/local-app-analysis/`. No running vendor process was
attached to or modified for this trace. The executable itself is not included.

## Protocol evidence in installed CortexService

Binary path, SHA256 and symbols: `../archive/current-state/local-app-analysis/cortex-symbols.json`.

| Routine/address | Finding | Local evidence |
|---|---|---|
| `getDecryptSerial`, 0x10105a568 | Firmware >=0x73f uses hex serial bytes | `v4-key.txt` |
| `generateAesKeyVersion4`, 0x10105ad04 | SHA256 of protocol seeds, uppercase first eight serial hex characters and four-digit revision | `v4-key.txt` |
| `findKey`, 0x10105bff0 | Recovers fixed protocol seeds and XOR byte from built-in constants | `find-key.txt` |
| `decryptNewPack`, 0x1010b55e0 | XOR first, AES-256 decrypt aligned blocks, XOR-only remainder | `packet-routines.txt` |
| `processAES`, 0x10105a1f0 | AES-256 ECB decrypt, no IV | `base-decrypt.txt` |
| Parser, 0x10109c670 | Splits EEG bytes into 32-byte records | `parse-scale.txt` |
| `convert_pkgs_EpocPlusMode`, 0x10105bab0 | Counter, type/flag header extraction | `convert-eeg.txt` |
| `unpack_bits_plusMode`, 0x10105be5c | EEG type 0x10: 15 unsigned little-endian words | `convert-eeg.txt` |
| `getRawEegId`, 0x101070d24 | EPOC X mode uses 14 ADC word indices excluding index 7 | `channel-layout.txt`, `layout-constants.txt` |
| `convertADCToMicrovolt`, 0x1010bfef8 | Scale divisor depends on device configuration; 7.8 divisor enabled only for the exact observed configuration | `parse-scale.txt` |

## Channel mapping evidence (2026-09-14)

`InputDevice::setDefaultChannels` branches for headset type 7 to 0x100fe9984.
The EEG output QList at 0x1033f11c0 is initialized at 0x100ff2544 using the
enum table at 0x10274ea04. Its first three entries are metadata; the next 14
are electrode IDs, whose names are established by the map initializer at
0x101fd47b8. `EpocXDataOutput::makeEEG` writes those output columns in order
using offsets 0x174, 0x178, 0x17c, 0x180, 0x184, 0x188, 0x190, 0x194,
0x198, 0x19c, 0x1a0, 0x1a4, 0x1a8, 0x1ac. Those are populated from
`getRawEegId`; its EPOC X constants give the word indices below.

| Electrode | ADC word index (zero-based, after the 2-byte header) |
|---|---|
| AF3 | 2 |
| F7 | 3 |
| F3 | 0 |
| FC5 | 1 |
| T7 | 4 |
| P7 | 5 |
| O1 | 6 |
| O2 | 8 |
| P8 | 9 |
| T8 | 10 |
| FC6 | 13 |
| F4 | 14 |
| F8 | 11 |
| AF4 | 12 |

Evidence: `default-channels.txt`, `default-branch-table.txt`,
`default-list-init-full.txt`, `output-eeg-enums.txt`, `channel-map-values.txt`,
`eeg-output.txt`, `channel-layout.txt`, `layout-constants.txt`, all under
`../archive/current-state/local-app-analysis/`. The static map was later verified against identical Cortex samples; see VALIDATION.md.


## Contact-quality routine findings

See archive/current-state/CONTACT_QUALITY.md and local-app-analysis/cq-*.txt.
headsetTypeFromVersion 0x101fc9180 maps 0x07xx to type 7; isCqInRawData
0x1010714a0 accepts type 7 via mask 0x14d. calculateCqChannelId 0x101f25dc4
uses counter modulo sample_rate/2. Type 7 init branch 0x101067810 sets 14
channels. getRawEegId 0x101070d24 routes CQ to raw word 7. updateCQStates
0x1010690bc contains normalization/threshold comparisons. Upstream/state
qualification is incomplete; see CONTACT_QUALITY.md.

## Encrypted Parquet findings

- ParquetCrypto::decrypt: 0x101203f58.
- ParquetFileReader::open: 0x1011f1d08.
- ParquetDecryptionKeyRetriever::v1: 0x1012031f8.
- GetKey: 0x101203328; three colon-separated fields, version 1.
- generateKey: 0x101203004; SHA256 over namespace and metadata components.

Targeted traces: parquet-crypto.txt, parquet-key-format.txt,
parquet-key-derivation.txt. The reconstructed helper uses standard Parquet
reader authentication rather than implementing its own encryption container.
