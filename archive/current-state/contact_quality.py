"""Conservative CQ transport extraction for the observed EPOC X configuration.

Static source evidence in CONTACT_QUALITY.md. Electrode labels follow the static trace. No quality classes until
calibration and an independent comparison are checked.
"""
from decoder import CONFIG_CHARACTERISTIC, REVISION_CHARACTERISTIC, metadata_bytes

# init builds CQ entries in this order; values contain raw EEG indices.
# See cq-init-states.txt, 0x101067a44 through 0x10106803c.
CQ_ELECTRODES = ("AF3", "F7", "F3", "FC5", "T7", "P7", "O1",
                 "O2", "P8", "T8", "FC6", "F4", "F8", "AF4")

class ContactQuality:
    def __init__(self, info):
        self.enabled = (metadata_bytes(info, REVISION_CHARACTERISTIC) == bytes.fromhex('0740')
                        and CONFIG_CHARACTERISTIC in info
                        and metadata_bytes(info, CONFIG_CHARACTERISTIC) == bytes.fromhex('018000102010'))
        self.slots = {}
        self.last_index = None

    def update(self, sample):
        if not self.enabled:
            return None
        index = sample.get('stream_index', sample['index'])
        if not sample['continuous'] or (self.last_index is not None and index != self.last_index + 1):
            self.slots.clear()
        self.last_index = index
        slot = sample['counter'] % 64
        if slot >= 14:
            return None
        raw = sample['adc_words'][7]
        self.slots[slot] = raw
        return {'kind':'contact_quality_raw', 'sample_index':index,
                'counter':sample['counter'], 'slot':slot, 'raw_value':raw,
                'received_at':sample['received_at'], 'observed_slots':len(self.slots),
                'basis':'official_static_trace_observed_configuration',
                'electrode':CQ_ELECTRODES[slot], 'quality_level':None,
                'mapping_basis':'official_software_static_trace',
                'calibration_verified':False, 'reference_validated':False}
