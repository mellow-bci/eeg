# Prospective audio-cued eyes experiment

2026-09-15, EPOC X near M4. Participant confirmed wearing prepared headset and audible M4/M3 speaker checks before capture. Actual cues used M4. The Python direct acquisition pipeline recorded 27,880 samples over217.44seconds: zero decode errors, two counter discontinuities, no connection interruptions;27,590 samples marked transport stable.

Twelve randomized10-second post-speech trials completed, six per eyes condition. All12 trimmed windows passed descriptive transport criteria. Median relative8–13Hz /1–40Hz power at O1/O2:

| Cue | O1 | O2 |
|---|---:|---:|
| Eyes open | 0.136853 | 0.130637 |
| Eyes closed | 0.096936 | 0.149239 |

This is mixed channel behavior, not evidence of a reliable sensory-state classifier. The participant reported **missed or uncertain cues**. Labels are unverified, and the run is **excluded from training and accuracy evaluation**. No cognitive score, mental command or HID output was validated/enabled.

The raw capture SHA256 matched the M4 source after transfer. Plan,actual events,raw bytes,decoded samples,summary and self-report are retained. `description.json` is reproducible with `python -m calibration.describe_trials capture.jsonl --output NEW.json` using analysis dependencies. Source acquisition version is the in-development bounded-consumer Python pipeline; no consumer was attached. Native app acquisition was not used for this experiment.

The runner received additional abort/cue-hardening after this run. Preserve the raw event chronology as evidence rather than assuming current code is byte-identical to the executed script.
