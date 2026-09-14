import json,tempfile,unittest
from pathlib import Path
from processing.workflow import new_jsonl,load_dataset,evaluate_profile
class WorkflowTests(unittest.TestCase):
    def test_atomic_failed_output_not_published(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'result.jsonl'
            with self.assertRaises(ValueError):
                with new_jsonl(p) as f:f.write('partial');raise ValueError('input corrupt')
            self.assertFalse(p.exists());self.assertEqual(list(Path(d).iterdir()),[])
            with new_jsonl(p) as f:f.write('{}\n')
            self.assertEqual(p.stat().st_mode&0o777,0o600)
            with self.assertRaises(FileExistsError):
                with new_jsonl(p):pass
    def test_unsupported_dataset_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'dataset.json';p.write_text('{}')
            with self.assertRaises(ValueError):load_dataset(p)
    def test_cross_manifest_content_rejected(self):
        p={'training_sessions':['A'],'training_window_ids':['a'],'training_recording_hashes':{'A':'x'}}
        with self.assertRaisesRegex(ValueError,'EEG content'):
            evaluate_profile(p,[{'session_id':'B','window_id':'b','recording_content_sha256':'x'}])
if __name__=='__main__':unittest.main()

class EndToEndSoftwareTests(unittest.TestCase):
    """Synthetic ADC recordings exercise plumbing, never neural-intent validation."""
    def test_recording_features_train_holdout_profile_and_replay(self):
        import numpy as np
        from processing.contract import CHANNELS,CONFIG_UUID,SUPPORTED_CONFIG
        from processing.workflow import windows_from
        from processing.mental import train,save_profile,load_profile,Detector
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);sessions=[]
            for session_index in range(3):
                rng=np.random.default_rng(401+session_index)
                path=root/f'synthetic-{session_index}.jsonl';trials=[]
                with path.open('w') as stream:
                    stream.write(json.dumps({'kind':'stream_start','epoch':1,'info':{CONFIG_UUID:SUPPORTED_CONFIG}})+'\n')
                    for window in range(20):
                        label='neutral' if window<10 else 'task'
                        trials.append({'id':f't{window}','start':window*2,'end':window*2+2,
                                       'label':label,'accepted':True,'label_verified':True})
                        t=np.arange(256)/128
                        volts=np.full((256,14),4200.)
                        for frequency in (2,6,10,20,35):
                            amplitudes=(8 if label=='neutral' else 25)*rng.uniform(.95,1.05,14)
                            volts+=np.sin(2*np.pi*frequency*t[:,None]+np.arange(14)[None,:]*.2)*amplitudes
                        volts+=rng.normal(0,.2,volts.shape)
                        for offset,row in enumerate(volts):
                            i=window*256+offset;counts=np.rint(row*7.8).astype(int);adc=dict(zip(CHANNELS,counts.tolist()))
                            row=counts/7.8
                            stream.write(json.dumps({'kind':'eeg_adc','units':'unsigned_adc_counts',
                                'index':i,'stream_index':i,'counter':i%128,'received_at':i/128,
                                'epoch':1,'stable_segment':1,'transport_stable':True,'continuous':True,
                                'electrodes_adc':adc,'electrodes_microvolts':dict(zip(CHANNELS,row.tolist()))})+'\n')
                    stream.write(json.dumps({'kind':'summary','samples':5120})+'\n')
                sessions.append({'id':f's{session_index}','split':'evaluation' if session_index==2 else 'train',
                                 'recording':path.name,'independent_session':True,'trials':trials})
            manifest=root/'dataset.json';manifest.write_text(json.dumps({'schema':'eeg.dataset.v1','participant_id':'synthetic','sessions':sessions}))
            participant,groups,provenance=load_dataset(manifest)
            self.assertEqual([len(groups[k]) for k in ('train','evaluation')],[40,20])
            profile=train(groups['train'],participant)
            # Runtime diagnostics cannot change model identity.
            for row in groups['train']:row['processing_seconds']=999.
            self.assertEqual(profile,train(groups['train'],participant))
            profile_path=root/'profile.json';save_profile(profile,profile_path)
            report=evaluate_profile(load_profile(profile_path),groups['evaluation'])
            self.assertEqual(len(report['predictions']),20)
            self.assertFalse(report['mental_command_hardware_validated'])
            self.assertIsNone(report['ordinary_activity_false_activations_per_hour'])
            controls=[dict(r,condition='ordinary_activity') for r in groups['evaluation'] if r['label']=='neutral']
            control_report=evaluate_profile(profile,controls,controls_only=True)
            self.assertEqual(control_report['evaluation_scope'],'controls_only')
            self.assertEqual(control_report['shadow_measurements']['conditions']['ordinary_activity']['trials'],10)
            with self.assertRaises(ValueError):evaluate_profile(profile,groups['evaluation'],controls_only=True)
            detector=Detector(profile)
            replay=[detector.infer(row) for row in windows_from(root/'synthetic-2.jsonl','s2','synthetic')]
            self.assertEqual(replay,[p['event'] for p in report['predictions']])
            self.assertTrue(any('experimental_candidate' in e for e in replay))
            self.assertTrue(all(e['command'] is None and not e['system_control_enabled'] for e in replay))
            with self.assertRaisesRegex(ValueError,'sessions overlap'):evaluate_profile(profile,groups['train'])
