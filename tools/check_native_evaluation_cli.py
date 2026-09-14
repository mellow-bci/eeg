#!/usr/bin/env python3
"""Exercise the native CLI with generated synthetic recordings, never a headset."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="eeg-native-cli-") as temporary:
    fixture = Path(temporary) / "fixture"
    env = dict(os.environ, EEG_NATIVE_EVALUATION_TEST_EXPORT=str(fixture))
    subprocess.run([
        "swift", "test", "--package-path", str(ROOT / "apple"), "--filter",
        "TrainingDatasetTests.testRecordingsAndLabelsTrainNativeProfileWithoutEvaluationLeakage"
    ], cwd=ROOT, env=env, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=300)
    executable = ROOT / "apple/.build/debug/EEGEvaluate"
    arguments = [str(executable), "--manifest", str(fixture / "manifest.json"),
                 "--profile", str(fixture / "profile.json"), "--recordings", str(fixture)]
    result = subprocess.run(arguments, capture_output=True, timeout=120)
    assert result.returncode == 0, result.stderr.decode()
    assert result.stdout == (fixture / "expected.json").read_bytes(), "CLI differs from canonical evaluator"
    receipt = json.loads(result.stdout)
    assert len(receipt["predictions"]) == 20
    assert receipt["system_control_enabled"] is False
    for args, status in [([str(executable), "--unknown"], 2),
                         (arguments + ["--controls-only"], 1),
                         (arguments + ["--manifest", "duplicate"], 2)]:
        failed = subprocess.run(args, capture_output=True, timeout=120)
        assert failed.returncode == status, failed.stderr.decode()
        assert not failed.stdout, "Failure leaked a provisional receipt"
        assert failed.stderr, "Failure omitted diagnostics"
    (fixture / "manifest.json").write_text("{}")
    failed = subprocess.run(arguments, capture_output=True, timeout=120)
    assert failed.returncode == 1 and not failed.stdout
print("Native CLI matches canonical synthetic evaluation; invalid inputs emit no receipt.")
