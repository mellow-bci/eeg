from fixture_support import fixture_path
"""Synthetic format/error tests only; not a vendor-reference validation."""
import csv,tempfile,unittest
from pathlib import Path
from reference_csv import inspect
from contact_quality import CQ_ELECTRODES
class ReferenceTests(unittest.TestCase):
 def fixture(self,path,mode='valid'):
  columns=['Timestamp','EEG.Counter','EEG.Interpolated']+['EEG.'+c for c in CQ_ELECTRODES]+['CQ.'+c for c in CQ_ELECTRODES]
  if mode=='missing':columns.remove('CQ.AF3')
  with path.open('w',newline='') as out:
   writer=csv.writer(out);writer.writerow(['headset serial:synthetic','sampling rate:128'])
   writer.writerow(columns)
   for i in range(3):
    row={k:2 for k in columns};row.update({'Timestamp':100+i/128,'EEG.Counter':(127+i)%128,'EEG.Interpolated':int(i==1)})
    if mode=='nan':row['EEG.AF3']='nan'
    if mode=='time':row['Timestamp']=100
    writer.writerow([row[k] for k in columns])
 def test_valid_wrap_keeps_interpolation_visible(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'synthetic.csv';self.fixture(p);r=inspect(p)
   self.assertEqual(r['samples'],3);self.assertEqual(r['interpolated_samples'],1)
   self.assertEqual(r['counter_discontinuities'],0);self.assertFalse(r['decoder_validated'])
 def test_rejects_incomplete_or_corrupt_reference(self):
  with tempfile.TemporaryDirectory() as d:
   for mode in ('missing','nan','time'):
    with self.subTest(mode=mode):
     p=Path(d)/'synthetic.csv';self.fixture(p,mode)
     with self.assertRaises(ValueError):inspect(p)
