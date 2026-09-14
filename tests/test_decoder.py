from fixture_support import fixture_path
import json
import unittest
from pathlib import Path
from decoder import Decoder, ProtocolError, SERIAL_CHARACTERISTIC, REVISION_CHARACTERISTIC

CAPTURE = fixture_path('ble-capture.json')


class RealCaptureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.capture = json.loads(CAPTURE.read_text())

    def test_entire_real_capture(self):
        decoder = Decoder(self.capture['info'])
        auxiliary = 0
        for packet in self.capture['packets']:
            samples, extra = decoder.decode(bytes.fromhex(packet['hex']))
            self.assertEqual(len(samples), 2)
            self.assertTrue(all(sample['continuous'] for sample in samples))
            self.assertEqual(len(samples[0]['adc_words']), 15)
            self.assertEqual(len(samples[0]['eeg_adc']), 14)
            auxiliary += extra is not None
        self.assertEqual(decoder.sample_count, 1588)
        self.assertEqual(decoder.discontinuities, 0)
        self.assertEqual(auxiliary, 396)

    def test_known_initial_adc_fixture(self):
        decoder = Decoder(self.capture['info'])
        samples, _ = decoder.decode(bytes.fromhex(self.capture['packets'][0]['hex']))
        self.assertEqual(samples[0]['counter'], 0)
        self.assertEqual(samples[0]['adc_words'], [32768] * 7 + [0] + [32768] * 7)
        self.assertEqual(samples[1]['adc_words'][:3], [32772, 32770, 32775])
        # Vendor output mapping differs from physical wire order.
        self.assertEqual(samples[1]['electrodes_adc']['AF3'], 32775)
        self.assertEqual(samples[1]['electrodes_adc']['F3'], 32772)
        self.assertEqual(samples[1]['electrodes_adc']['FC5'], 32770)

    def test_wrong_serial_rejected(self):
        info = dict(self.capture['info'], **{SERIAL_CHARACTERISTIC: '000000002b'})
        decoder = Decoder(info)
        with self.assertRaises(ProtocolError):
            decoder.decode(bytes.fromhex(self.capture['packets'][0]['hex']))
        self.assertEqual(decoder.sample_count, 0)

    def test_unsupported_revision_rejected(self):
        info = dict(self.capture['info'], **{REVISION_CHARACTERISTIC: '0730'})
        with self.assertRaises(ProtocolError):
            Decoder(info)

    def test_truncation_rejected(self):
        decoder = Decoder(self.capture['info'])
        with self.assertRaises(ProtocolError):
            decoder.decode(bytes.fromhex(self.capture['packets'][0]['hex'])[:-1])

    def test_gap_is_reported(self):
        decoder = Decoder(self.capture['info'])
        decoder.decode(bytes.fromhex(self.capture['packets'][0]['hex']))
        samples, _ = decoder.decode(bytes.fromhex(self.capture['packets'][2]['hex']))
        self.assertFalse(samples[0]['continuous'])
        self.assertTrue(samples[1]['continuous'])
        self.assertEqual(decoder.discontinuities, 1)

    def test_duplicate_packet_is_not_continuous(self):
        decoder = Decoder(self.capture['info'])
        packet = bytes.fromhex(self.capture['packets'][0]['hex'])
        decoder.decode(packet)
        samples, _ = decoder.decode(packet)
        self.assertFalse(samples[0]['continuous'])

    def test_header_checks_do_not_prove_body_integrity(self):
        # Changing an ECB block that contains no header can evade structural
        # checks. Preserve this limitation explicitly; never claim a MAC/CRC.
        original = bytes.fromhex(self.capture['packets'][0]['hex'])
        changed = bytearray(original)
        changed[20] ^= 1
        good, _ = Decoder(self.capture['info']).decode(original)
        altered, _ = Decoder(self.capture['info']).decode(bytes(changed))
        self.assertNotEqual(good[0]['adc_words'], altered[0]['adc_words'])
        self.assertEqual(good[0]['counter'], altered[0]['counter'])
        self.assertFalse(altered[0]['integrity_verified'])

class VoltageTests(unittest.TestCase):
    def test_observed_configuration_applies_vendor_scale_without_centering(self):
        from decoder import CONFIG_CHARACTERISTIC
        capture = json.loads(CAPTURE.read_text())
        info = dict(capture['info'], **{CONFIG_CHARACTERISTIC: '018000102010'})
        sample = Decoder(info).decode(bytes.fromhex(capture['packets'][0]['hex']))[0][0]
        self.assertEqual(sample['electrodes_adc']['AF3'], 32768)
        self.assertAlmostEqual(sample['electrodes_microvolts']['AF3'], 4201.025641025641)
        self.assertFalse(sample['physiology_validated'])

    def test_unobserved_configuration_does_not_guess_scale(self):
        from decoder import CONFIG_CHARACTERISTIC
        capture = json.loads(CAPTURE.read_text())
        for config in ('', '0180000e2010', '018000102011'):
            info = dict(capture['info'], **{CONFIG_CHARACTERISTIC: config})
            sample = Decoder(info).decode(bytes.fromhex(capture['packets'][0]['hex']))[0][0]
            self.assertNotIn('electrodes_microvolts', sample)


if __name__ == '__main__':
    unittest.main()
