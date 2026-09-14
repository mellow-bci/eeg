# Native spectrum parity fixtures

These are private numerical verification inputs, not new participant experiments.

- `real.json`: first valid canonical 256-sample window from the previously authorized
  `archive/current-state/epoc-cortex-retest-20260915-01.jsonl`; selected electrode O1.
  The recording SHA-256 is included in fixture provenance. Native samples preserve
  original wire words, channel mapping and arrival timestamps.
- `sine10.json`: quantized synthetic ADC = round(31200 + 156 sin(2π10i/128)),
  microvolts = ADC / 7.8, i=0…255. Selected electrode AF3. No physiological meaning.

Expected PSD is `scipy.signal.welch(x, fs=128, window='hann', nperseg=256,
noverlap=0, detrend='linear', scaling='density')`. RMS and peak-to-peak use
`scipy.signal.detrend(x, type='linear')`. Expected integrated log-band powers come
from `processing.features.extract_matrix` on the complete 256×14 voltage matrix.
These fixtures expose every input and expected bin, not only a chart screenshot.

Native tests compare all 129 one-sided bins, five half-open bands, RMS and
peak-to-peak. Default PSD tolerance is max(1e-9, |expected|×1e-8), log-power 1e-7,
RMS/peak-to-peak 1e-8. No hardware is accessed. The benchmark prints warm single-channel
compute time; it excludes BLE, display, initial basis generation and end-to-end latency.

`EEGSpectrum` has no epoch/config metadata beyond EEGSample's calibrated values.
The app must additionally gate by recorded or live transport context. Flags apply to
the selected electrode and use unvalidated independent artifact thresholds. They are
not contact-quality, emotion, engagement or mental-state scores.

`real-features.json` contains the full 70-value Python oracle for `real.json`,
including exact feature names and configuration hash. Regenerate it with
`python -m tools.generate_native_mental_fixture` from repository root.
