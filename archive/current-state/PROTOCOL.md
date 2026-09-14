# Direct EPOC X acquisition: verified firmware 0740 path

This is an independent Python acquisition/decoding implementation. It does not
launch Cortex, call its cloud API, use an account credential, or require the
official apps at runtime. Static analysis of the user's installed official
CortexService on M4 supplied protocol evidence; the real BLE capture on M3
supplied the validation data. No firmware or vendor app was modified.

## What works

`stream.py` provides the same packet-to-sample pipeline for BLE and file replay.
The saved hardware capture has 794 notifications, 1,588 EEG sample records,
396 auxiliary records, zero rejected packets and zero counter discontinuities.
The sample arrival rate is approximately 128.05 samples/second over 12.386 seconds,
consistent with 128 Hz. This is not a claim to expose the ADC's internal 2048 Hz.

Fresh live collection and decoding succeeded together at 18:12 UTC on 2026-09-14:
1,920 notifications produced 3,840 sample records over 30 seconds, zero decode
errors or counter gaps, approximately 128.054 Hz. See
`live-charged-20260914T181205Z.jsonl`. Physiological validation remains pending.

## Scope and output

- Device metadata: serial characteristic 2a25 has five bytes; software revision
  characteristic 2a28 is `0740`. Other firmware revisions are rejected until tested.
- BLE notification characteristic: `81072f41-9f3d-11e3-a9dc-0002a5d5c51b`.
- Supported notification lengths: 64 and 84 bytes only.
- Each contains two 32-byte EEG records. An 84-byte notification additionally
  contains a 20-byte auxiliary record, preserved without interpreting motion units.
- EEG header: byte 0 is counter modulo 128; low seven bits of byte 1 are type 0x10;
  the high bit is preserved as a flag without assigning an unverified meaning.
- The next 30 bytes are 15 unsigned little-endian 16-bit words.
- The vendor's EPOC X channel-index table and voltage conversion select 14 words:
  indices 0..6 and 8..14. Word 7 is preserved separately, not called EEG.
- Output includes all 15 original words plus the 14 EEG ADC values in wire order,
  and `electrodes_adc` labeled by the official software mapping below.
  Raw units remain ADC counts. For the exact observed configuration, additional
  `electrodes_microvolts` values use the traced vendor division, without centering.
  Mapping and conversion are software-verified, not independently calibrated.
- Arrival timestamps are host notification timestamps. Both samples share that
  timestamp and have an explicit slot; we do not invent device sample timestamps.
- Wrong serial, unsupported firmware, malformed length/type and intra-packet
  counter errors reject the packet. Across-packet gaps are explicitly flagged.
- AES ECB has no authentication tag: header/counter checks detect many errors,
  but are not a cryptographic integrity guarantee.
  A deliberate body-corruption regression test confirms that modified blocks
  can preserve valid headers/counters. Samples explicitly set
  `integrity_verified: false`; this does not mean observed corruption was found.

## Protocol evidence in installed CortexService

Binary path, SHA256 and symbols: `local-app-analysis/cortex-symbols.json`.

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
`local-app-analysis/`. This closes the software mapping trace; a known-input
or worn-headset reference test remains independent validation.

## Run

From this directory, with a virtual environment containing `requirements.txt`:

```sh
python stream.py --replay ble-capture.json --output replay-new.jsonl
python stream.py --seconds 30 --attempts 3 --output live-new.jsonl
python -m unittest discover -s . -p 'test_*.py' -v
```

Use `--device` with a known CoreBluetooth identifier to try an already discovered
headset directly. Output files are exclusive-create to preserve earlier captures.
Live runs read metadata before subscribing, retry connection failures and preserve
reconnection boundaries. Output flushes after each JSONL event.
Every connection has an explicit epoch; sample `index` is local to that epoch,
while `stream_index` increases across the whole output file. Summaries preserve
per-epoch arrival boundaries and sample counts. Reconnection-boundary tests use
recorded packets and do not establish hardware recovery.

## Remaining validation

1. Unexpected radio-loss and extended-duration reliability checks. Fresh live
   decoding, a two-minute run and three deliberate reconnect cycles have passed
   connection/recovery checks, with startup losses explicitly retained.
2. Independently validate the traced electrode mapping, configuration-dependent µV scale and contact-quality
   fields against a vendor reference or known input.
3. Worn-headset validation, including electrode contact and controlled artifacts.
   Off-head ADC output is not proof of valid physiological EEG.
4. Only afterward: signal processing, user calibration, intent inference and
   explicit confirmed actions through CAST / Apple BCI HID. These are separate
   downstream capabilities, not implemented by this acquisition module.

## Voltage scaling trace (2026-09-14)

The divisor selector is the configured EEG resolution: typed setHeadsetConfig
argument 3 is stored at AbstractInputDevice+0xc4; getInputDeviceInfo copies
this+0x30, preserving returned +0x94; createDataProcessingObject copies that
into DataProcessOption+0xac; the correction constructor copies the option
at this+8, resulting in correction+0xb4. convertADCToMicrovolt tests this
against 16, choosing divisor 7.8 for 16 and 1.95 otherwise. The byte-array
configuration parser reads resolution from byte 3 on its applicable path.
Evidence: resolution-config.txt, processing-option-init.txt,
device-info-copy.txt and ble-config-read.txt in local-app-analysis.
The original capture lacks configuration bytes and remains ADC-only. New
captures with the exact verified `018000102010` configuration additionally
include uncentered vendor-scaled microvolts (ADC / 7.8). Other configurations
stay ADC-only; no bit depth is inferred from signal ranges.

The configuration UUID is now verified as
`81072f44-9f3d-11e3-a9dc-0002a5d5c51b` by initializer 0x100f8d4b4.
extractEmotivInfos stores its value at this+0x7e8; service completion forwards
it through vtable +0x98 (0x100f82678) to the configuration parser.
`stream.py` reads and preserves this value with a five-second timeout; errors
are logged without preventing ADC acquisition. This read succeeded on hardware. Earlier captures lack it and stay ADC-only.

Fresh configuration read at 18:12 UTC: `018000102010`. Byte 3 is 16,
selecting the statically traced 7.8 divisor. The acquisition file preserves raw
ADC values; independent reference comparison remains outstanding.

## Stream quality and recovery

Every original packet is retained. Rejected packets remain decode_error events;
no counter checks have been relaxed. Samples start with transport_stable=false.
After at least 256 contiguous samples AND two seconds of host time, the pipeline
emits transport_status=stable. A rejected packet or counter gap resets this
state. This is a transport continuity gate, not a signal/contact-quality score.
Summaries distinguish capture_clean, stable_samples, and transport_stable_at_end.
A recovered stream may have capture_clean=false because startup data was lost.

A connected device that supplies no notifications for five seconds is marked
as interrupted, disconnected by the client context and retried within --attempts.
--cycles performs deliberate reconnect captures, retaining distinct epochs and
monotonic stream_index values. It does not simulate an unexpected radio outage.
Per-epoch observed arrival rates include startup buffering; they are not a
measurement of the internal ADC clock. A single rate is omitted across epochs.

The 14 software tests include real recorded startup anomalies, voltage conversion
and a simulated silent transport watchdog. Simulation tests are labeled as such.
See VALIDATION.md for hardware observations and outstanding work.
