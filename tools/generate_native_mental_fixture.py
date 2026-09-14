"""Regenerate the native full-vector oracle from the recorded spectrum fixture.

Run from repository root: python -m tools.generate_native_mental_fixture
Requires the research environment's numpy/scipy. No synthetic physiology is added.
"""
import json
from pathlib import Path
from processing.features import extract_matrix, NAMES
from processing.contract import CHANNELS


def main():
    folder = Path(__file__).resolve().parents[1] / 'apple/Fixtures/spectrum'
    source = json.loads((folder / 'real.json').read_text())
    matrix = [[sample['electrodesMicrovolts'][channel] for channel in CHANNELS]
              for sample in source['samples']]
    result = extract_matrix(matrix)
    result['names'] = NAMES
    (folder / 'real-features.json').write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
