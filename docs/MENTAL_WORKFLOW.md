# Independent mental-command processing v1

**Implemented experimental software, not a hardware-validated mental-command model.** No trained participant profile is shipped. No OS, HID, Cast or vendor API is invoked by this workflow. Existing raw captures are preserved.

## One processing contract

`processing.contract` explicitly adapts Python reference JSONL and Swift `eeg-native-v1` JSONL into immutable canonical samples. `processing.windows` produces nonoverlapping256-sample windows. `processing.workflow.windows_from` is the shared route for feature extraction, dataset building and replay inference. Native capture never runs Python; this first inference implementation is an offline Python research consumer of the explicit canonical adapter. A native trained-inference port remains future work.

## Evidence versus design

The reference body trace confirms a feature-selection/PCA/canonical/Gaussian-density/posterior path in selected Cortex routines. It does not establish all window, spectral, training, score or timing parameters. See MENTAL_REFERENCE_TRACE.md. The parameters below are defaults in [PROCESSING_SETTINGS.md](PROCESSING_SETTINGS.md), stored with each profile. Every parameter is **our independent experimental design**, not an approximation silently presented as recovered Cortex behavior.

| Component | Explicit implementation |
|---|---|
| Input | Observed128Hz configuration only;14 named electrodes; original ADC and optional observed-config uV remain distinct |
| Window |256samples, no overlap; complete stable continuous same-epoch/config windows required; partial tails rejected |
| Spectrum | SciPy Welch, Hann256, no overlap, linear detrend, density normalization; no resampling/interpolation |
| Features |70 log10 integrated power features:14channels × bands1–4,4–8,8–13,13–30,30–40Hz; power floor1e-12uV² |
| Artifact flags | Any detrended channel peak-to-peak>500uV or RMS>100uV; flat/rail/nonfinite rejection. Thresholds are unvalidated conservative engineering defaults, not blink/jaw classifiers. |
| Training acceptance | Explicit accepted and verified labels; neutral plus one or more task classes; at least20 windows/class across at least2 sessions; same feature/config/participant; unique windows and canonical recording content |
| Scaling/selection | Training-only mean/std; between/within variance ratio ranks70features; select20 deterministically |
| PCA | Training-only SVD, up to8components; deterministic sign convention; no recovered canonical transform is claimed or substituted |
| Gaussian model | Per-class mean and diagonal variance in PCA space; variance floor0.05; equal priors |
| Scoring | Log Gaussian density normalized across classes; scores are **uncalibrated**, not psychological confidence |
| Rejection | Invalid/artifact input, participant/config mismatch, ambiguous score(<0.9 or margin<0.25), modeled-space distance beyond training-derived bound, or insufficient persistence |
| Persistence | Two consecutive nonoverlapping accepted windows; reset across time/session gaps and rejected inputs. Minimum window accumulation≈4s; measured end-to-end latency remains unknown |
| Profile | Versioned JSON with design, transforms, class statistics, participant, training session/content hashes and optional retraining parent; private exclusive file; checksum detects accidental modification, not malicious authentication |
| Application proposal | `eeg.command-proposal.v1`; source/session/window/profile/config, candidate scores and reason. `status=no_reliable_command`, `command=null`, `system_control_enabled=false` until a separately validated release exists |

The Gaussian distance check observes only retained PCA space; it cannot detect every out-of-distribution artifact. Unknown physiological artifacts remain a limitation even when amplitude flags are clear.

## Reproduce

Install base and analysis requirements. Run from repository root:

```sh
python -m processing.workflow extract CAPTURE.jsonl --session SESSION --participant LOCAL_ID --output WINDOWS.jsonl
python -m processing.workflow train DATASET.json --output PROFILE.json
python -m processing.workflow evaluate DATASET.json --profile PROFILE.json --output REPORT.json
python -m processing.workflow replay CAPTURE.jsonl --profile PROFILE.json --session NEW_SESSION --participant LOCAL_ID --output PROPOSALS.jsonl
```

Dataset schema:

```json
{"schema":"eeg.dataset.v1","participant_id":"local-id","sessions":[
 {"id":"independent-session-id","recording":"capture.jsonl","split":"train","independent_session":true,
  "trials":[{"id":"trial1","start":20.0,"end":30.0,"label":"neutral","accepted":true,"label_verified":true}]}
]}
```

The abbreviated example deliberately does not satisfy training/evaluation sample gates. Add actual separately acquired and verified trials; never duplicate data to satisfy counts. Split whole sessions using `train`/`evaluation`. Only windows fully contained in declared intervals are assigned labels. Invalid training windows are counted and rejected; invalid evaluation windows remain rejection outcomes. Class labels name a specific trained task, not an inferred emotion.

## Evaluation and limits

Reports include per-class precision/recall, trial/session counts, rejection fraction, cued neutral exposure/false-positive windows, processing latency and every proposal. Processing latency excludes acquisition/Bluetooth/user response. Calibration wall time and participant-level uncertainty intervals remain null when unmeasured; correlated windows are not substituted for independent subjects. Window outcomes within a trial are correlated; do not interpret window count as independent participant observations. Ordinary-activity false activations/hour stays null until an actual ordinary-activity evaluation exists. There is no automatic hardware-validation flag from a good offline score.

Record hashes block full-capture reuse across changed filenames/serialization; they cannot independently prove session independence or exclude every partial reuse. Participant declarations are not objective behavioral measurement. The latest uncertain-cue eyes capture is excluded from model training. Neural command claims require prospective separated sessions plus blink/jaw/head-motion controls and continuous neutral exposure.

`--parent-profile` accepts a previously saved profile path and validates its participant before storing its profile ID as retraining lineage. Feature timing diagnostics are excluded from model identity, so repeated extraction does not change the profile hash solely because CPU timing differs.

## Shadow measurements

[SHADOW_EVALUATION.md](SHADOW_EVALUATION.md) defines condition-specific episode counts, exposure, cue-associated latency and conditional false-activation upper bounds. Use `evaluate --controls-only` for explicitly labeled neutral challenge/ordinary-activity sessions; no dummy task trials are required. A prospective task protocol is documented in [MENTAL_QUALIFICATION_PROTOCOL.md](MENTAL_QUALIFICATION_PROTOCOL.md). No experiment is started by these documents.

### Numerical and provenance rejection checkpoint — 2026-09-15

Profile loading validates nonempty unique training-window identities and the format
of the training-record digest after checking profile integrity. Recomputing a hash
does not make malformed metadata valid; neither check proves the truth of labels.
Inference requires explicit session/window identities. Missing identities reset
candidate persistence and return `missing_recording_identity`.

Finite feature values can overflow normalization or Gaussian distances. The detector
now traps numerical failure, clears candidate persistence, returns
`numerical_failure`, and omits class scores rather than serializing NaN or presenting
an arbitrary winning class. The next acceptable window must begin persistence again.
These software regression tests use manufactured vectors and do not validate neural
intent. Run `python -m unittest discover -s tests` in the research environment.

### Canonical construction boundary

Direct `CanonicalSample` construction now enforces the same unsigned integral ADC
counts and observed-configuration voltage conversion as the recording adapter.
Epoch/segment identifiers must be nonnegative integers or unknown; transport flags
must be actual booleans. Missing source identity is rejected before event adaptation
rather than converted into strings such as `None`. Unknown metadata remains allowed
as unknown and is rejected by the valid-window gate, never promoted to readiness.
The full Python suite passed 119 tests after this change.
