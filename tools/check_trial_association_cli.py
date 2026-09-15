#!/usr/bin/env python3
"""Check the complete synthetic trial fixture exported by the native test.

Usage: python3 tools/check_trial_association_cli.py FIXTURE_DIRECTORY
The native test's EEG_TRIAL_ASSOCIATION_TEST_EXPORT produces these files.
No hardware, acquisition, vendor runtime or inference implementation is added.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('fixture', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
fixture = args.fixture.resolve()
expected = (fixture / 'expected.json').read_bytes()
manifest = json.loads((fixture / 'manifest.json').read_text())
assert len(manifest['sessions']) == 1
source = manifest['sessions'][0]
assert source['recording'] == Path(source['recording']).name
recording = fixture / source['recording']
digest = hashlib.sha256(recording.read_bytes()).hexdigest()
assert digest == source['file_sha256']
command = [str(root / 'apple/.build/debug/EEGEvaluate'), '--manifest', str(fixture / 'manifest.json'),
           '--profile', str(fixture / 'profile.json'), '--recordings', str(fixture),
           '--trial-association-minimum-eligible-fraction', '0.8']
completed = subprocess.run(command, capture_output=True, timeout=180)
assert completed.returncode == 0, completed.stderr.decode()
assert completed.stdout == expected, 'CLI differs from canonical fixture receipt'
receipt = json.loads(completed.stdout)
assessment = receipt['trial_association'][source['id']]
assert assessment['status'] == 'conditional_only_exchangeability_unverified'
result = assessment['result']
assert result['sourceFileSHA256'] == digest
assert result['minimumEligibleFraction'] == 0.8
association = result['association']
ids = association['orderedTrialIDs']
assert len(ids) == len(set(ids)) == 24
trials = {t['trial_id']: t for t in receipt['trials']}
assert set(trials) == set(ids)
outcomes = [trials[t]['contained_candidate_windows'] > 0 for t in ids]
assert association['candidateObserved'] == outcomes
observed = sum(trials[t]['label'] == 'silent_serial_subtraction' and outcome
               for t, outcome in zip(ids, outcomes))
assert association['observedTaskCandidateTrials'] == observed
counts = association['scheduleCountsByTaskCandidateTrials']
assert sum(counts) == association['admissibleSchedules'] == 705982
assert sum(counts[observed:]) == association['atLeastObservedSchedules']
for trial in trials.values():
    fraction = trial['eligible_seconds'] / (trial['end_seconds'] - trial['start_seconds'])
    assert fraction >= 0.8
    assert result['eligibleFractionsByTrialID'][trial['trial_id']] == min(1, fraction)
assert receipt['system_control_enabled'] is False
assert receipt['hardware_validated'] is False
print('Complete 24-trial synthetic CLI receipt matches canonical evaluation; source and outcome accounting verified. No physiological qualification.')
