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

At the documented checkpoint, **29 tests passed** on the development host. The repository has additional portable test support and must be rerun after copying. Record actual results rather than keeping a hardcoded count as a gate.

## Hardware qualification remains separate

Never equate `unittest` success with live discovery, permission onboarding, scalp contact, operating-system reliability or clinical validity. Live test records and hashes are included under the archive and evidence manifest. See VALIDATION.md for measured results and RELEASE_GATES.md for what remains.
