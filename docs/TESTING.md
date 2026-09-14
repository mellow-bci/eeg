# Testing and reproduction

## Environment

Python 3.9, bleak 1.1.1, pycryptodome 3.23.0, PyObjC 11.1 on Apple Silicon macOS were used. Optional analysis uses numpy 2.0.2/scipy 1.13.1; Parquet recovery uses pyarrow 19.0.1. Dependency pins are recorded in the requirements files. Version support beyond the observed setup has not been established.

```sh
git lfs pull
.venv/bin/python -m unittest discover -s tests -p 'test_*.py' -v
```

`fixture_support.py` resolves real recordings in `archive/current-state` by default. `CHORUS_EEG_FIXTURES` can select another authorized exact fixture directory. Missing fixtures cause explicitly reported skips. A skipped hardware-dependent test is not a passed hardware test. LFS pointers must be hydrated before reproduction.

## What the tests mean

- Real capture replay checks actual saved byte payloads, expected initial ADC words, channel mapping, scaling, counter continuity, rejected startup packets and stable-only delivery across epochs.
- Deliberate encrypted-body corruption demonstrates that ECB header checks do not establish body authentication.
- Synthetic CSV fixtures test parsing, interpolation accounting and malformed input rejection; they are not vendor reference data.
- Mock Bluetooth clients test silence and callback failures without claiming new hardware observations.
- A subprocess test sends SIGTERM to a fake-transport acquisition process and checks shutdown/summary persistence.
- File ownership, size budget, exclusive creation and device lease behavior are exercised locally.

The original acquisition checkpoint passed29 tests. The expanded suite adds native replay/storage, canonical adapters, malformed-data rejection, audio-runner failure handling and synthetic model/workflow tests. See the dated processing qualification report in `evidence/processing-qualification.json` for the current measured checkpoint. Always rerun after changes; counts alone are not a release gate.

## Hardware qualification remains separate

Never equate `unittest` success with live discovery, permission onboarding, scalp contact, operating-system reliability or clinical validity. Live test records and hashes are included under the archive and evidence manifest. See VALIDATION.md for measured results and RELEASE_GATES.md for what remains.

## Expanded processing and native checks

```sh
python -W error::ResourceWarning -m unittest discover -s tests -p 'test_*.py' -v
swift test --package-path apple
./apple/build-native.sh all
```

The end-to-end software test generates three explicitly synthetic ADC recordings, separates training from evaluation by recording, serializes/reloads a profile and checks deterministic replay proposals. It tests plumbing and failure gates; its class separation is manufactured and is not evidence of neural intent. No synthetic model is shipped as a participant profile.
