"""Manufactured training records and Python oracle; no physiological evidence."""
import json
from pathlib import Path
import sys
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tests.test_mental_processing import records
from processing.mental import train

rows = records()
for row in rows:
    row['usable'] = True
profile = train(rows, 'participant')
x = np.asarray([row['values'] for row in rows])
chosen = ((x-np.asarray(profile['center']))/np.asarray(profile['scale']))[:,profile['selected']]
fixture = {'records': rows, 'expected': {key: profile[key] for key in ('classes','center','scale','selected','pca_mean')},
           'fitted': profile, 'centered_selected': (chosen-np.asarray(profile['pca_mean'])).tolist()}
path = Path(__file__).resolve().parents[1]/'apple/Fixtures/spectrum/mental-training.json'
path.write_text(json.dumps(fixture, indent=2, allow_nan=False)+'\n')
print(path)
