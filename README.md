# EEG

Independent EPOC X Bluetooth EEG acquisition, decoding, local-recording recovery and validation research. This is the complete work snapshot through **2026-09-15**, not a claim of production or clinical certification.

**Current result:** all **15,108 transport-stable samples** in a fresh two-minute simultaneous recording matched Cortex across all 14 electrode ADC values, in order. The maximum voltage difference was **0.000237881 µV**. All 15,361 matched samples, including matched startup data, also matched raw contact quality. Startup anomalies were preserved and quarantined.

**Release status: NOT RELEASED.** Longer standalone qualification, real hardware fault tests, quality-class calibration and release packaging remain. Working raw acquisition is established; neural intent, clinical validity and Apple BCI/HID integration are not.

## Native Apple application

The native SwiftUI workspace is in `apple/`, targeting macOS, iOS and visionOS. It uses Swift/CoreBluetooth directly; Python remains the independent reference and research environment. See [native app](docs/NATIVE_APP.md), [feature matrix](docs/FEATURE_MATRIX.md) and [Apple integration boundaries](docs/APPLE_PLATFORM.md).

[Calibration and evaluation](docs/COGNITIVE_VALIDATION.md) separates sensory-state experiments, intentional gestures and neural intent. No cognitive score or system-control output is enabled.

## Evidence-backed expansion checkpoint

The [capability matrix](capability-matrix.json) and [ordered plan](docs/IMPLEMENTATION_PLAN.md) separate discovered symbols, inspected bodies, implementation, software tests and hardware validation. The [independent mental workflow](docs/MENTAL_WORKFLOW.md) now provides canonical windows, spectral features, personalized PCA/Gaussian profiles, holdout evaluation and read-only proposals. No trained mental-command model or validated cognitive score is shipped. [Reference trace](docs/MENTAL_REFERENCE_TRACE.md) records both confirmed function-body behavior and unresolved parameters.

## Contents and reading order

| Document | Purpose |
|---|---|
| [Current state](docs/CURRENT_STATE.md) | Verified capabilities, limits, exact scope |
| [Architecture](docs/ARCHITECTURE.md) | End-to-end ownership and the single acquisition path |
| [Protocol](docs/PROTOCOL.md) | GATT, key derivation, byte layouts, channel map, units |
| [Runtime algorithms](docs/RUNTIME.md) | Stability, timing, consumer gate, failures, leases, shutdown |
| [Data contract](docs/DATA_CONTRACT.md) | Existing acquisition JSONL events, indices and flags |
| [Canonical processing contract](docs/DATA_CONTRACT_V2.md) | Shared live-event/replay adapter, windows and provenance |
| [Contact quality](docs/CONTACT_QUALITY.md) | Raw extraction, static trace and unresolved classification |
| [Reference recovery](docs/REFERENCE_RECOVERY.md) | TEST24 recovery, authenticated Parquet, snapshot procedure |
| [Comparison](docs/COMPARISON.md) | Exact matching algorithm and its limits |
| [Signal experiments](docs/SIGNAL_EXPERIMENTS.md) | Eye/blink cues, Welch power, detrended RMS and observations |
| [Validation](docs/VALIDATION.md) | Capture-by-capture measured results |
| [Testing](docs/TESTING.md) | Real fixtures vs synthetic fault injection; reproducing tests |
| [Operations](docs/OPERATIONS.md) | Setup, permissions, live capture, troubleshooting |
| [Release gates](docs/RELEASE_GATES.md) | Remaining production work and acceptance rules |
| [Research history](docs/RESEARCH_HISTORY.md) | What was tried, corrected and rejected |
| [Evidence trace](docs/EVIDENCE_TRACE.md) | Static routines, binary identity and evidence locations |
| [Data handling](docs/DATA_HANDLING.md) | Private recordings, Git LFS, provenance and exclusions |
| [Source map](docs/SOURCE_MAP.md) | Every component and historical tool |

## Clone and reproduce

```sh
git lfs install
git clone https://github.com/autonomy-cloud/eeg.git
cd eeg
git lfs pull
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt -r requirements-analysis.txt
.venv/bin/python -m unittest discover -s tests -p 'test_*.py' -v
```

The environment used for implementation was Python 3.9 on Apple Silicon macOS. Hardware fixtures are included in the private archive through LFS. Without LFS content, fixture-dependent tests must not be interpreted as passing hardware validation.

## Capture

From a desktop Terminal on the Mac connected to the headset:

```sh
.venv/bin/python probe_connected.py
.venv/bin/python stream.py --device YOUR-LOCAL-COREBLUETOOTH-ID --seconds 120 --attempts 3 --output recordings/run-001.jsonl
```

Create `recordings/` before running. Grant Bluetooth access through normal macOS privacy UI. CoreBluetooth IDs are host-local. The operational entry point is **stream.py**; research tools are not alternate production acquisition services.

The archive contains personal EEG data and device identity. **Keep this repository private.** [Data policy](docs/DATA_HANDLING.md).
