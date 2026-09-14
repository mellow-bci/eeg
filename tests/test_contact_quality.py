from fixture_support import fixture_path
import unittest
from contact_quality import ContactQuality
from decoder import CONFIG_CHARACTERISTIC,REVISION_CHARACTERISTIC
class ContactQualityTests(unittest.TestCase):
 def make(self):return ContactQuality({CONFIG_CHARACTERISTIC:'018000102010',REVISION_CHARACTERISTIC:'0740'})
 def sample(self,c,i=None):return {'index':c if i is None else i,'counter':c,'continuous':True,'adc_words':[0]*7+[123]+[0]*7,'received_at':1.0}
 def test_slots_wrap_and_unused(self):
  q=self.make()
  self.assertEqual(q.update(self.sample(0))['slot'],0)
  self.assertEqual(q.update(self.sample(13))['slot'],13)
  self.assertIsNone(q.update(self.sample(14)))
  self.assertEqual(q.update(self.sample(64))['slot'],0)
  self.assertIsNone(q.update(self.sample(127)))
 def test_gap_invalidates_history(self):
  q=self.make();q.update(self.sample(0));q.update(self.sample(1))
  s=self.sample(3);s['continuous']=False
  self.assertEqual(q.update(s)['observed_slots'],1)
 def test_unknown_config_no_labels(self):
  q=ContactQuality({REVISION_CHARACTERISTIC:'0740'})
  self.assertIsNone(q.update(self.sample(0)))
  e=self.make().update(self.sample(0))
  self.assertEqual(e['raw_value'],123);self.assertEqual(e['electrode'],'AF3');self.assertIsNone(e['quality_level'])
