# Observed EPOC X BLE protocol

Implementation: [decoder.py](../decoder.py). This describes the exact observed
software revision/configuration, not a universal EPOC-family specification.

## Discovery and GATT

| Item | UUID / observed representation |
|---|---|
| EPOC service | `81072f40-9f3d-11e3-a9dc-0002a5d5c51b` |
| EEG notification | `81072f41-9f3d-11e3-a9dc-0002a5d5c51b` |
| Configuration read | `81072f44-9f3d-11e3-a9dc-0002a5d5c51b` |
| Serial read | `00002a25-0000-1000-8000-00805f9b34fb`, five raw bytes |
| Software revision read | `00002a28-0000-1000-8000-00805f9b34fb`, `0740` |
| Firmware characteristic observed separately | `00002a26-0000-1000-8000-00805f9b34fb`, `0730` |
| Supported configuration | `018000102010` |

No configuration is written. Unsupported revision/serial length is rejected.
Configuration other than the exact supported bytes leaves data ADC-only.

## Device-key derivation, exactly as implemented

Let `P` be the fixed protocol byte string in `derive_key()`:

```text
55db7062edcd83c155214df357dd918b43ef0e12f34c
28bb26f9630d40dde902ab83e448db890d295228e414
```

The lines concatenate to one hex string. These are static protocol constants,
not GitHub/account/cloud credentials.

1. `T = P[-12:]`.
2. `Kseed = SHA256(T)`.
3. `S = AES-256-ECB-decrypt(Kseed, P[:32])` with no padding removal.
4. `H = uppercase(serial.hex())[:8]`, encoded as ASCII. The fifth serial byte is
   retained in metadata but does not appear in these eight serial characters.
5. Concatenate Python-slice byte ranges:
   `M = S[1:4] || S[5:10] || H[:4] || S[11:18] || S[19:20] || H[4:] || uppercase(revision.hex()).ASCII`.
6. `Kdevice = SHA256(M)`; byte mask `X = T[-1]`.

The implementation explicitly accepts revision bytes `07 40`; it does not select
an arbitrary firmware branch based on a version string provided by a caller.

## Notification decode

Only lengths 64 or 84 bytes are accepted.

```text
transformed[i] = notification[i] XOR X
aligned = floor(len(transformed)/16) * 16
plain = AES-256-ECB-decrypt(Kdevice, transformed[:aligned]) || transformed[aligned:]
```

For 84-byte notifications, 80 bytes are AES-decrypted and the last four bytes
have only the XOR transform. EEG records are `plain[0:32]` and `plain[32:64]`.
The optional auxiliary record is `plain[64:84]`.

## EEG record structure

| Offset within 32-byte record | Meaning |
|---|---|
| 0 | Counter, constrained to 0…127 |
| 1 bits 0…6 | Must equal `0x10` |
| 1 bit 7 | Preserved `record_flag`; semantics not claimed |
| 2…31 | Fifteen unsigned little-endian 16-bit words |

Both records are validated **before either updates decoder state**. Their counters
must differ by one modulo 128. For an 84-byte notification, auxiliary byte 1
(`plain[65]`) must have low seven bits `0x20`. A structurally invalid notification
is rejected in full. Across notifications, a nonconsecutive counter is flagged
rather than silently repaired, sorted, interpolated or discarded.

## Electrode mapping and voltage

ADC word indices are relative to the 15-word array after the two-byte header.

| Electrode | Word | Electrode | Word |
|---|---:|---|---:|
| AF3 | 2 | O2 | 8 |
| F7 | 3 | P8 | 9 |
| F3 | 0 | T8 | 10 |
| FC5 | 1 | FC6 | 13 |
| T7 | 4 | F4 | 14 |
| P7 | 5 | F8 | 11 |
| O1 | 6 | AF4 | 12 |

Word **7 is raw contact quality**, not EEG. Named electrode output is distinct
from the wire-order array with word 7 removed.

For `018000102010`, byte 3 is decimal 16, consistent with the traced resolution
selector. The supported conversion is **microvolts = unsigned ADC / 7.8**.
Values remain uncentered; no DC subtraction, filter, artifact cleaning or
normalization occurs in acquisition. The statically observed alternate divisor
1.95 is not enabled for unqualified configurations.

The observed stream is about 128 samples/second. Host arrival rate includes
startup buffering and scheduling; it is not the internal ADC clock. No 2048 Hz
access is implemented.

## Integrity limit

ECB has no authentication tag. Wrong keys commonly fail header checks, but a
modified body block can preserve valid headers and counters. A regression test
explicitly demonstrates this. `integrity_verified:false` is correct even after
sample agreement with Cortex; that agreement does not add a MAC to the protocol.

See [Evidence trace](EVIDENCE_TRACE.md) for static routine locations and
[Comparison](COMPARISON.md) for empirical validation of the map and scale.
