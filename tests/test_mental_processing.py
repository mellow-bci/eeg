"""Synthetic numerical/state tests only; these do not validate physiology or intent."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import numpy as np
from processing.features import CONFIG_ID, NAMES, extract_matrix
from processing.mental import DESIGN, Detector, digest, load_profile, save_profile, train, validate_profile


def records():
    rng=np.random.default_rng(19)
    result=[]
    for session in ('train-a','train-b'):
        for label,mean in [('neutral',0.),('task',4.)]:
            for i in range(20):
                result.append({'accepted':True,'label_verified':True,'artifact_flags':[],
                    'feature_config_id':CONFIG_ID,'participant_id':'participant',
                    'window_id':f'{session}-{label}-{i}','session_id':session,'label':label,
                    # Synthetic provenance only: not a hardware recording digest.
                    'recording_content_sha256':hashlib.sha256(session.encode()).hexdigest(),
                    'values':(mean+rng.normal(0,.15,len(NAMES))).tolist()})
    return result


def inference(value,start=0):
    return {'values':np.full(len(NAMES),value).tolist(),'feature_config_id':CONFIG_ID,
            'artifact_flags':[],'usable':True,'participant_id':'participant',
            'session_id':'future-test','continuity_id':'future-segment-1','window_id':f'future-{start}', 'start':start,'end':start+2}


def resigned(profile):
    result=copy.deepcopy(profile)
    result.pop('profile_id',None)
    result['profile_id']=digest(result)
    return result


class ProfileLineageTests(unittest.TestCase):
    def test_optional_parent_and_malformed_lineage(self):
        rows = records()
        profile = train(rows, 'participant')
        validate_profile(profile)
        child = train(rows, 'participant', parent_profile=profile['profile_id'])
        validate_profile(child)
        self.assertEqual(child['parent_profile_id'], profile['profile_id'])
        self.assertNotEqual(child['profile_id'], profile['profile_id'])
        for bad in ('invalid', 'A'*64, '', 42, True, [], {}):
            with self.subTest(parent=bad):
                with self.assertRaises(ValueError):
                    train(rows, 'participant', parent_profile=bad)
                changed = dict(child, parent_profile_id=bad)
                with self.assertRaises(ValueError):
                    validate_profile(resigned(changed))


class FeatureTests(unittest.TestCase):
    def test_known_sine_power_and_input_unchanged(self):
        t=np.arange(256)/128
        values=np.tile((4200+20*np.sin(2*np.pi*10*t))[:,None],(1,14))
        original=values.copy()
        feature=extract_matrix(values)
        np.testing.assert_array_equal(values,original)
        self.assertTrue(feature['usable'])
        # Integrated 10 Hz sine energy is A^2/2, allowing tiny detrend leakage.
        self.assertAlmostEqual(10**feature['values'][2],200,delta=2)
        self.assertEqual(len(feature['values']),70)
        self.assertIsNone(feature['cognitive_interpretation'])

    def test_artifact_flat_and_invalid_inputs(self):
        t=np.arange(256)/128
        values=np.tile((4200+400*np.sin(2*np.pi*10*t))[:,None],(1,14))
        self.assertFalse(extract_matrix(values)['usable'])
        self.assertIn('flat_channel',extract_matrix(np.full((256,14),4200))['artifact_flags'])
        for invalid in (np.zeros((256,14)),np.full((256,14),np.nan),np.ones((128,14))):
            with self.assertRaises(ValueError):extract_matrix(invalid)


class MentalTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.training=records()
        cls.profile=train(cls.training,'participant')

    def test_transforms_only_use_supplied_training_and_do_not_mutate(self):
        data=copy.deepcopy(self.training)
        before=copy.deepcopy(data)
        profile=train(data,'participant')
        np.testing.assert_allclose(profile['center'],np.array([r['values'] for r in data]).mean(axis=0))
        self.assertEqual(data,before)
        self.assertEqual(profile['training_sessions'],['train-a','train-b'])
        detector=Detector(profile)
        for value in (10000,4,0):detector.infer(inference(value))
        self.assertEqual(profile,train(data,'participant'))
        self.assertIsNot(profile['design'],DESIGN)

    def test_no_arbitrary_window_or_task_class_cap(self):
        # Manufactured records exercise availability, not classifier performance.
        data=[]
        for i in range(10001):
            source=self.training[i%len(self.training)]
            data.append(dict(source,window_id=f'synthetic-large-{i}'))
        profile=train(data,'participant')
        self.assertEqual(len(profile['training_window_ids']),10001)
        expanded=[]
        for class_index in range(7):
            for source in self.training:
                if source['label']!='neutral':continue
                expanded.append(dict(source,label='neutral' if class_index==0 else f'task-{class_index}',
                                     window_id=f"{class_index}-{source['window_id']}",
                                     values=(np.asarray(source['values'])+class_index).tolist()))
        self.assertEqual(len(validate_profile(train(expanded,'participant'))['classes']),7)

    def test_class_session_label_and_feature_requirements(self):
        variants=[]
        data=copy.deepcopy(self.training);data[0]['label_verified']=False;variants.append(data)
        data=copy.deepcopy(self.training);data[0]['artifact_flags']=['artifact'];variants.append(data)
        data=copy.deepcopy(self.training);data[0]['feature_config_id']='different';variants.append(data)
        data=copy.deepcopy(self.training);data[0]['participant_id']='other';variants.append(data)
        data=copy.deepcopy(self.training);data[0]['window_id']=data[1]['window_id'];variants.append(data)
        variants.append([r for r in self.training if r['label']=='task'])
        variants.append([r for r in self.training if r['session_id']=='train-a'])
        variants.append([r for r in self.training if r['label']=='neutral']+[r for r in self.training if r['label']=='task'][:19])
        for data in variants:
            with self.subTest(case=len(data)):
                with self.assertRaises(ValueError):train(data,'participant')

    def test_recording_content_provenance_rejects_missing_mixed_and_duplicate_sessions(self):
        for invalid in ('missing','malformed','mixed','duplicate'):
            data=copy.deepcopy(self.training)
            if invalid=='missing':data[0].pop('recording_content_sha256')
            if invalid=='malformed':data[0]['recording_content_sha256']='not-a-hash'
            if invalid=='mixed':data[0]['recording_content_sha256']='f'*64
            if invalid=='duplicate':
                for row in data:row['recording_content_sha256']='a'*64
            with self.subTest(invalid=invalid):
                with self.assertRaises(ValueError):train(data,'participant')
        self.assertEqual(set(self.profile['training_recording_hashes']),{'train-a','train-b'})
        profile=copy.deepcopy(self.profile)
        profile['training_recording_hashes']['train-b']=profile['training_recording_hashes']['train-a']
        with self.assertRaises(ValueError):validate_profile(resigned(profile))

    def test_neutral_ood_and_ambiguous_rejected(self):
        self.assertEqual(Detector(self.profile).infer(inference(0))['reason'],'neutral')
        self.assertEqual(Detector(self.profile).infer(inference(10000))['reason'],'out_of_training_distribution')
        profile=copy.deepcopy(self.profile)
        for gaussian in profile['gaussians']:
            gaussian['mean']=[0.]*8;gaussian['variance']=[100.]*8;gaussian['distance_limit']=1e9
        result=Detector(resigned(profile)).infer(inference(2))
        self.assertEqual(result['reason'],'ambiguous_score')
        self.assertIsNone(result['command'])

    def test_persistence_candidate_never_enables_command(self):
        detector=Detector(self.profile)
        self.assertEqual(detector.infer(inference(4))['reason'],'insufficient_persistence')
        result=detector.infer(inference(4,2))
        self.assertEqual(result['experimental_candidate'],'task')
        self.assertIsNone(result['command'])
        self.assertFalse(result['system_control_enabled'])
        self.assertEqual(result['status'],'no_reliable_command')

    def test_gap_session_artifact_and_bad_timing_reset_persistence(self):
        for invalid in ('gap','session','segment','artifact','timing','features'):
            detector=Detector(self.profile)
            detector.infer(inference(4))
            row=inference(4,2)
            if invalid=='gap':row=inference(4,10)
            if invalid=='session':row['session_id']='new-session'
            if invalid=='segment':row['continuity_id']='new-segment'
            if invalid=='artifact':row['artifact_flags']=['flat_channel']
            if invalid=='timing':row['end']=float('nan')
            if invalid=='features':row['values']=['invalid']*70
            result=detector.infer(row)
            self.assertNotIn('experimental_candidate',result)
            if invalid in ('artifact','timing','features'):
                self.assertEqual(detector.infer(inference(4,2))['reason'],'insufficient_persistence')

    def test_profile_isolation_after_detector_creation(self):
        profile=copy.deepcopy(self.profile)
        detector=Detector(profile)
        profile['scale'][0]=0
        profile['design']['persistence_windows']=1
        self.assertEqual(detector.infer(inference(4))['reason'],'insufficient_persistence')
        self.assertEqual(DESIGN['persistence_windows'],2)

    def test_profile_roundtrip_private_no_overwrite_and_integrity(self):
        with tempfile.TemporaryDirectory() as root:
            path=Path(root)/'profile.json'
            save_profile(self.profile,path)
            self.assertEqual(load_profile(path),self.profile)
            self.assertEqual(path.stat().st_mode & 0o777,0o600)
            original=path.read_bytes()
            with self.assertRaises(FileExistsError):save_profile(self.profile,path)
            self.assertEqual(path.read_bytes(),original)
            profile=copy.deepcopy(self.profile);profile['center'][0]+=1
            path.write_text(json.dumps(profile))
            with self.assertRaises(ValueError):load_profile(path)

    def test_resigned_malformed_or_enabled_profile_rejected(self):
        for change in ('enabled','design','scale','components','selection','variance','label','schema'):
            profile=copy.deepcopy(self.profile)
            if change=='enabled':profile['system_control_enabled']=True
            if change=='design':profile['design']['persistence_windows']=1
            if change=='scale':profile['scale'][0]=0
            if change=='components':profile['components'][0]=[1.]
            if change=='selection':profile['selected'][0]=profile['selected'][1]
            if change=='variance':profile['gaussians'][0]['variance'][0]=-1
            if change=='label':profile['gaussians'][0]['label']='mismatch'
            if change=='schema':profile['schema']='unsupported'
            with self.subTest(change=change):
                with self.assertRaises(ValueError):validate_profile(resigned(profile))


class NumericalRejectionTests(unittest.TestCase):
    def test_extreme_finite_features_reject_without_nan_or_persistence(self):
        detector=Detector(train(records(),'participant'))
        self.assertEqual(detector.infer(inference(4,0))['reason'],'insufficient_persistence')
        result=detector.infer(inference(1e308,2))
        self.assertEqual(result['reason'],'numerical_failure')
        self.assertNotIn('experimental_candidate',result)
        self.assertNotIn('uncalibrated_class_scores',result)
        json.dumps(result,allow_nan=False)
        self.assertEqual(detector.infer(inference(4,4))['reason'],'insufficient_persistence')

    def test_profile_provenance_fields_are_validated_after_integrity(self):
        baseline=train(records(),'participant')
        for value in (None,[],['duplicate','duplicate'],[42],['']):
            profile=copy.deepcopy(baseline);profile['training_window_ids']=value
            with self.subTest(value=value),self.assertRaises(ValueError):
                validate_profile(resigned(profile))
        for value in (None,'not-a-digest',42):
            profile=copy.deepcopy(baseline);profile['training_records_sha256']=value
            with self.subTest(value=value),self.assertRaises(ValueError):
                validate_profile(resigned(profile))

    def test_missing_recording_identity_rejects_and_resets_candidate(self):
        profile=train(records(),'participant')
        for key in ('session_id','window_id'):
            for value in (None,'',42):
                detector=Detector(profile)
                detector.infer(inference(4,0))
                row=inference(4,2);row[key]=value
                result=detector.infer(row)
                self.assertEqual(result['reason'],'missing_recording_identity')
                self.assertNotIn('experimental_candidate',result)
                self.assertEqual(detector.infer(inference(4,4))['reason'],'insufficient_persistence')
