"""Direct EPOC X BLE firmware 0740 decoder, reconstructed from local vendor code.

Only the observed 64/84-byte notification format is supported. Outputs ADC
words, not calibrated physiology or inferred intent. See PROTOCOL.md for evidence.
"""
import hashlib
import struct
from Crypto.Cipher import AES

SERVICE = '81072f40-9f3d-11e3-a9dc-0002a5d5c51b'
DATA_CHARACTERISTIC = '81072f41-9f3d-11e3-a9dc-0002a5d5c51b'
SERIAL_CHARACTERISTIC = '00002a25-0000-1000-8000-00805f9b34fb'
REVISION_CHARACTERISTIC = '00002a28-0000-1000-8000-00805f9b34fb'
CONFIG_CHARACTERISTIC = '81072f44-9f3d-11e3-a9dc-0002a5d5c51b'

# Official EPOC X makeEEG output order + getRawEegId word indices.
# See PROTOCOL.md's channel mapping evidence; never assume display == wire order.
ELECTRODE_WORDS = (
    ('AF3', 2), ('F7', 3), ('F3', 0), ('FC5', 1), ('T7', 4),
    ('P7', 5), ('O1', 6), ('O2', 8), ('P8', 9), ('T8', 10),
    ('FC6', 13), ('F4', 14), ('F8', 11), ('AF4', 12),
)


class ProtocolError(ValueError):
    pass


def metadata_bytes(info, uuid):
    value = info.get(uuid)
    if isinstance(value, dict):
        value = value.get('hex')
    if not isinstance(value, str):
        raise ProtocolError('Required device metadata missing: ' + uuid)
    return bytes.fromhex(value)


def derive_key(serial, revision):
    if len(serial) != 5 or revision != bytes.fromhex('0740'):
        raise ProtocolError('Only the observed five-byte serial / 0740 firmware is supported')
    # Static protocol constants from CortexService::findKey, not account secrets.
    packed = bytes.fromhex(
        '55db7062edcd83c155214df357dd918b43ef0e12f34c'
        '28bb26f9630d40dde902ab83e448db890d295228e414')
    tail = packed[-12:]
    seed = AES.new(hashlib.sha256(tail).digest(), AES.MODE_ECB).decrypt(packed[:32])
    serial_hex = serial.hex().upper()[:8].encode('ascii')
    material = (seed[1:4] + seed[5:10] + serial_hex[:4]
                + seed[11:18] + seed[19:20] + serial_hex[4:]
                + revision.hex().upper().encode('ascii'))
    return hashlib.sha256(material).digest(), tail[-1]


class Decoder:
    def __init__(self, info):
        key, self.xor_byte = derive_key(metadata_bytes(info, SERIAL_CHARACTERISTIC),
                                        metadata_bytes(info, REVISION_CHARACTERISTIC))
        self.cipher = AES.new(key, AES.MODE_ECB)
        self.previous_counter = None
        self.sample_count = 0
        self.discontinuities = 0
        # Only the configuration actually read from this firmware is enabled.
        # Preserve unsigned ADC and the vendor's uncentered voltage separately.
        self.voltage_divisor = None
        if CONFIG_CHARACTERISTIC in info:
            config = metadata_bytes(info, CONFIG_CHARACTERISTIC)
            if config == bytes.fromhex('018000102010'):
                self.voltage_divisor = 7.8

    def decode(self, payload, received_at=None):
        if len(payload) not in (64, 84):
            raise ProtocolError('Unsupported notification length: ' + str(len(payload)))
        transformed = bytes(value ^ self.xor_byte for value in payload)
        aligned = len(transformed) // 16 * 16
        plain = self.cipher.decrypt(transformed[:aligned]) + transformed[aligned:]
        records = [plain[:32], plain[32:64]]
        # Validate both records before emitting either; wrong serial keys fail here.
        if any(record[1] & 0x7f != 0x10 for record in records):
            raise ProtocolError('Unexpected EEG record type; key or format mismatch')
        if (records[1][0] - records[0][0]) % 128 != 1:
            raise ProtocolError('Invalid within-notification sample counters')
        if any(record[0] >= 128 for record in records):
            raise ProtocolError('Unsupported sample counter range')
        if len(plain) == 84 and plain[65] & 0x7f != 0x20:
            raise ProtocolError('Unexpected auxiliary record type')
        samples = []
        for slot, record in enumerate(records):
            counter = record[0]
            continuous = (self.previous_counter is None
                          or counter == (self.previous_counter + 1) % 128)
            if not continuous:
                self.discontinuities += 1
            words = list(struct.unpack('<15H', record[2:]))
            samples.append({
                'kind': 'eeg_adc', 'index': self.sample_count, 'counter': counter,
                'received_at': received_at, 'notification_slot': slot,
                'continuous': continuous, 'record_flag': record[1] >> 7,
                'adc_words': words, 'units': 'unsigned_adc_counts',
                # Vendor getRawEegId/convertADCToMicrovolt select all except word 7.
                # Electrode labels and calibrated voltage require separate validation.
                'eeg_adc': words[:7] + words[8:],
                'electrodes_adc': {name: words[index] for name, index in ELECTRODE_WORDS},
                'mapping_basis': 'official_software_static_trace',
                'other_word_7': words[7],
                'channel_order': 'wire_order_without_word_7',
                'integrity_verified': False,
                'physiology_validated': False,
            })
            if self.voltage_divisor is not None:
                samples[-1]['electrodes_microvolts'] = {
                    name: words[index] / self.voltage_divisor
                    for name, index in ELECTRODE_WORDS}
                samples[-1]['voltage_basis'] = 'official_conversion_observed_device_config'
                samples[-1]['voltage_centering'] = 'none'
            self.previous_counter = counter
            self.sample_count += 1
        auxiliary = None
        if len(plain) == 84:
            auxiliary = {'kind': 'auxiliary_raw', 'counter': plain[64],
                         'received_at': received_at, 'hex': plain[64:].hex()}
        return samples, auxiliary
