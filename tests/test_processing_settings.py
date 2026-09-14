import unittest
from processing.settings import validate_settings
from processing.mental import train,Detector,validate_profile
from test_mental_processing import records,inference

class SettingsTests(unittest.TestCase):
    def test_defaults_and_invalid_values(self):
        self.assertIsNone(validate_settings()['max_training_windows'])
        for value in ({'unknown':1},{'pca_components':71},{'persistence_windows':0},
                      {'score_threshold':2},{'variance_floor':float('nan')},
                      {'max_training_windows':False},{'schema':'future'}):
            with self.assertRaises(ValueError):validate_settings(value)

    def test_profile_owns_tuning_and_optional_budget(self):
        settings={'selected_features':10,'pca_components':4,'persistence_windows':1}
        profile=train(records(),'participant',settings=settings)
        settings['persistence_windows']=99
        self.assertEqual(profile['processing_settings']['persistence_windows'],1)
        self.assertEqual(len(profile['components']),4)
        validate_profile(profile)
        event=Detector(profile).infer(inference(4))
        self.assertEqual(event['experimental_candidate'],'task')
        self.assertIsNone(event['command'])
        self.assertFalse(event['system_control_enabled'])
        with self.assertRaisesRegex(ValueError,'resource budget'):
            train(records(),'participant',settings={'max_training_windows':10})

if __name__=='__main__':unittest.main()
