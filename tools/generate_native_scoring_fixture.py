"""Synthetic cross-language oracle; run python -m tools.generate_native_scoring_fixture.

Uses the existing numerical-test training recipe. Not a deployable participant model.
"""
import json
import sys
from pathlib import Path
from processing.mental import train, Detector


def main():
    root = Path(__file__).resolve().parents[1]
    sys.path.insert(0, str(root / 'tests'))
    from test_mental_processing import records, inference
    profile = train(records(), 'participant')
    output = {'provenance': 'Synthetic numerical parity only; not a participant profile or physiological validation.',
              'parameters': profile, 'cases': []}
    for value in [0, 1, 2, 3, 4, 10000]:
        record = inference(value)
        result = Detector(profile).infer(record)
        output['cases'].append({'values': record['values'],
            'scores': [result['uncalibrated_class_scores'][label] for label in profile['classes']],
            'label': result['candidate_label'], 'outside': result['reason'] == 'out_of_training_distribution'})
    (root / 'apple/Fixtures/spectrum/mental-scoring.json').write_text(json.dumps(output, indent=2) + '\n')
    (root / 'apple/Fixtures/spectrum/mental-profile.json').write_text(json.dumps(profile, indent=2) + '\n')


if __name__ == '__main__':
    main()
