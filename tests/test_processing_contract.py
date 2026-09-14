import json
import tempfile
import unittest
from dataclasses import FrozenInstanceError, replace
from pathlib import Path
from processing.contract import CHANNELS, CONFIG_UUID, SUPPORTED_CONFIG, iter_samples, iter_event_samples
from processing.windows import iter_windows


def events(native=False,count=512):
    if native:
        yield {'kind':'stream_start','schema':'eeg-native-v1'}
        yield {'kind':'device_metadata',CONFIG_UUID.upper():SUPPORTED_CONFIG}
        yield {'kind':'transport_status','status':'stable'}
    else:yield {'kind':'stream_start','epoch':1,'info':{CONFIG_UUID:SUPPORTED_CONFIG}}
    for i in range(count):
        adc={c:float(32000+i%20) for c in CHANNELS};volts={c:v/7.8 for c,v in adc.items()}
        if native:
            yield {'kind':'eeg_sample','sample':{'index':i,'counter':i%128,'receivedAt':i/128,
                   'continuous':True,'adcWords':[32000+i%20]*15,'electrodesADC':adc,'electrodesMicrovolts':volts}}
        else:yield {'kind':'eeg_adc','index':i,'stream_index':i,'counter':i%128,'received_at':i/128,
                    'epoch':1,'stable_segment':1,'transport_stable':True,'continuous':True,
                    'units':'unsigned_adc_counts','electrodes_adc':adc,'electrodes_microvolts':volts}
    yield {'kind':'summary','samples':count}


class ContractTests(unittest.TestCase):
    def test_native_and_python_have_identical_canonical_measurements(self):
        a=list(iter_event_samples(events(False),'same',True));b=list(iter_event_samples(events(True),'same',True))
        self.assertEqual(a,b)
        with self.assertRaises(FrozenInstanceError):a[0].index=2
        windows=list(iter_windows(a))
        self.assertEqual(len(windows),2)
        self.assertTrue(all(w.valid for w in windows))
        self.assertEqual(windows[0].samples[-1].index,255)
        self.assertEqual(windows[1].samples[0].index,256)

    def test_native_missing_status_stays_unstable(self):
        source=(e for e in events(True,256) if e['kind']!='transport_status')
        window=next(iter_windows(iter_event_samples(source,'native')))
        self.assertFalse(window.valid);self.assertIn('transport_unstable',window.reasons)

    def test_native_import_metadata_json_and_recovery_boundary(self):
        source=list(events(True,256))
        source[1]={'kind':'device_metadata','metadata_json':json.dumps({CONFIG_UUID:SUPPORTED_CONFIG})}
        source.insert(100,{'kind':'transport_status','status':'recovering'})
        source.insert(120,{'kind':'transport_status','status':'stable'})
        window=next(iter_windows(iter_event_samples(source,'n')))
        self.assertIn('source_or_segment_boundary',window.reasons)
        self.assertIn('transport_unstable',window.reasons)

    def test_invalid_window_reasons_explicit_no_interpolation(self):
        samples=list(iter_event_samples(events(False,257),'p'))
        samples[20]=replace(samples[20],counter=99,index=2000,config_id='unknown')
        windows=list(iter_windows(samples))
        self.assertIn('index_or_counter_gap',windows[0].reasons)
        self.assertIn('unsupported_configuration',windows[0].reasons)
        self.assertIn('partial_window',windows[1].reasons)
        self.assertEqual(len(windows[0].samples),256)
        with self.assertRaises(ValueError):list(iter_windows(samples,size=128))

    def test_unknown_schema_units_voltage_and_partial_file_rejected(self):
        variants=[]
        schema=list(events(True,1));schema[0]['schema']='future';variants.append(schema)
        units=list(events(False,1));units[1]['units']='volts';variants.append(units)
        mismatch=list(events(False,1));mismatch[1]['electrodes_microvolts']['AF3']=1;variants.append(mismatch)
        for source in variants:
            with self.assertRaises(ValueError):list(iter_event_samples(source,'p',True))
        with self.assertRaises(ValueError):list(iter_event_samples(list(events(False,1))[:-1],'p',True))
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'data.jsonl';path.write_text('{"kind":')
            with self.assertRaises(ValueError):list(iter_samples(path))

    def test_preambles_allowed_but_early_samples_rejected(self):
        preamble=[{'kind':'experiment_plan'},{'kind':'connection_attempt'},{'kind':'capture_cycle'}]
        self.assertEqual(len(list(iter_event_samples(preamble+list(events(False,2)),'p',True))),2)
        with self.assertRaises(ValueError):list(iter_event_samples([{'kind':'eeg_adc'}],'p'))

    def test_gap_exactly_at_window_boundary_is_invalid(self):
        samples=list(iter_event_samples(events(False,512),'p',True))
        for index in range(256,512):samples[index]=replace(samples[index],index=samples[index].index+1,counter=(samples[index].counter+1)%128)
        windows=list(iter_windows(samples))
        self.assertTrue(windows[0].valid)
        self.assertIn('index_or_counter_gap',windows[1].reasons)

    def test_summary_count_wire_consistency_and_mutable_sample_rejected(self):
        source=list(events(True,2));source[-1]['samples']=3
        with self.assertRaisesRegex(ValueError,'Summary sample count'):list(iter_event_samples(source,'p',True))
        source=list(events(True,2));source[3]['sample']['adcWords'][2]=1
        with self.assertRaisesRegex(ValueError,'ADC channel map'):list(iter_event_samples(source,'p',True))
        sample=next(iter_event_samples(events(False,1),'p'))
        with self.assertRaises(ValueError):replace(sample,adc=list(sample.adc))
        with self.assertRaises(ValueError):replace(sample,received_at=float('nan'))

    def test_file_source_identity_and_bounded_windows(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'data.jsonl'
            path.write_text(''.join(json.dumps(e)+'\n' for e in events(False,256)))
            samples=list(iter_samples(path))
            self.assertEqual(len(samples[0].source_id),64)
            self.assertTrue(next(iter_windows(samples)).valid)

class DirectCanonicalBoundaryTests(unittest.TestCase):
    def test_constructor_cannot_bypass_adapter_validation(self):
        sample=next(iter_event_samples(events(False,1),'source'))
        variants=[dict(transport_stable='false'),dict(continuous=1),dict(epoch=True),
            dict(stable_segment=-1),dict(received_at=-1),dict(config_id=42),
            dict(adc=None),dict(adc=(1.5,)*14),dict(adc=(65536.,)*14),
            dict(microvolts=(1.,)*14)]
        for fields in variants:
            with self.subTest(fields=fields),self.assertRaises(ValueError):replace(sample,**fields)
        unknown=replace(sample,epoch=None,stable_segment=None,config_id=None,microvolts=None)
        self.assertIsNone(unknown.microvolts)
        self.assertFalse(next(iter_windows([unknown])).valid)

    def test_missing_source_is_not_stringified_into_identity(self):
        for source in (None,42,False,''):
            with self.subTest(source=source),self.assertRaises(ValueError):
                list(iter_event_samples(events(False,1),source))

if __name__=='__main__':unittest.main()
