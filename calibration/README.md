# Calibration research tools

These tools acquire labeled experiments and evaluate **specific sensory/gesture targets**. They do not emit system input, cognitive scores or validated mental commands.

- `protocol.py`: reproducible balanced randomized audio plan; no hardware access.
- `run_audio.py`: macOS audio cues with actual timestamps inside the existing Python acquisition pipeline. Start only after participant confirms readiness and hears the sound check. Final cue opens eyes, including ordinary abort cleanup. A process crash cannot guarantee an audio cue.
- `describe_trials.py`: descriptive O1/O2 relative alpha features for actual completed eyes trials. Rejects unstable/gapped/unsupported-voltage windows. No model fitted.
- `evaluate.py`: predeclared eyes/gesture features and regularized LDA using whole-session holdout. Requires two training sessions, one test session, ten trials per class per split and literal verified-label declarations. Checks duplicate recordings and canonical EEG content. This cannot independently prove acquisition independence or participant compliance.

Run from repository root with `requirements.txt` and `requirements-analysis.txt` installed:

```sh
python -m calibration.protocol generate --protocol eyes_open_closed --seed 42 --output plan.json
python -m calibration.run_audio --run --plan plan.json --device LOCAL-BLUETOOTH-ID --output new-session.jsonl
python -m calibration.describe_trials new-session.jsonl --output description.json
python -m calibration.evaluate dataset.json --output evaluation.json
```

`dataset.json` schema (replace with real independently acquired sessions and actual post-cue time intervals):

```json
{
  "protocol": "eyes",
  "sessions": [
    {
      "session_id": "unique-session-id",
      "participant_id": "local-pseudonymous-id",
      "split": "train",
      "recording": "new-session.jsonl",
      "labels_verified": true,
      "trials": [
        {"trial_id": "trial-001", "label": "eyes_open", "start": 20, "end": 28}
      ]
    }
  ]
}
```

The example is intentionally insufficient for evaluation: add actual sessions/trials, never duplicate data to satisfy gates. `labels_verified` is an explicit operator declaration and should be backed by documented observations; hearing a cue is not proof that an action occurred. `eyes` uses eyes_open/eyes_closed. `blink` uses neutral/deliberate_blink and measures ocular artifacts, not pure neural intent.

Confidence intervals describe observed held-out trial outcomes. They do not establish continuous false activations/hour, population generalization, stress/attention validity or readiness to control an operating system. No report unlocks external output.
