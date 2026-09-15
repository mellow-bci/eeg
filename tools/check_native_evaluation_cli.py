#!/usr/bin/env python3
"""Exercise the native CLI with generated synthetic recordings, never a headset."""
import json
import math
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
    assert receipt["minimum_windows_per_class"] == 10
    relaxed = subprocess.run(arguments + ["--minimum-windows-per-class", "1"], capture_output=True, timeout=120)
    assert relaxed.returncode == 0, relaxed.stderr.decode()
    relaxed_receipt = json.loads(relaxed.stdout)
    assert relaxed_receipt["minimum_windows_per_class"] == 1
    assert relaxed_receipt["predictions"] == receipt["predictions"], "Count setting changed inference"
    assert len(receipt["predictions"]) == 40
    assert receipt["system_control_enabled"] is False
    # Recompute exposure from serialized windows rather than trusting two calls
    # to the same native exporter to agree. Distinct held-out sessions start at
    # the same receipt time and must remain separate in the report.
    assert set(receipt["session_conditions"]) == {"c", "d"}
    expected = {}
    for window in receipt["predictions"]:
        key = (window["session_id"], window["condition"])
        totals = expected.setdefault(key, {"eligible_seconds": 0.0,
            "rejected_seconds": 0.0, "unarmed_seconds": 0.0, "candidate_windows": 0})
        field = ("unarmed_seconds" if not window["shadow_enabled"] else
                 "rejected_seconds" if not window["input_usable"] else "eligible_seconds")
        totals[field] += window["end_seconds"] - window["start_seconds"]
        if window["predicted_label"] not in (None, "neutral"):
            totals["candidate_windows"] += 1
    for (session, condition), totals in expected.items():
        actual = receipt["session_conditions"][session][condition]
        for field, value in totals.items():
            assert math.isclose(actual[field], value, rel_tol=1e-12, abs_tol=1e-12), (session, condition, field)
    for condition, pooled in receipt["conditions"].items():
        for field in ("eligible_seconds", "rejected_seconds", "unarmed_seconds",
                      "candidate_windows", "episode_onsets", "carry_in_candidates"):
            total = sum(values.get(condition, {}).get(field, 0)
                        for values in receipt["session_conditions"].values())
            assert math.isclose(pooled[field], total, rel_tol=1e-12, abs_tol=1e-12), (condition, field)
    assert set(receipt["session_metrics"]) == {"c", "d"}
    groups = [(receipt["metrics"], receipt["predictions"])] + [
        (metrics, [r for r in receipt["predictions"] if r["session_id"] == session])
        for session, metrics in receipt["session_metrics"].items()]
    for metrics, rows in groups:
        for label, metric in metrics.items():
            tp = sum(r["actual_label"] == label and r["predicted_label"] == label for r in rows)
            fp = sum(r["actual_label"] != label and r["predicted_label"] == label for r in rows)
            fn = sum(r["actual_label"] == label and r["predicted_label"] != label for r in rows)
            assert (metric["true_positive"], metric["false_positive"], metric["false_negative"]) == (tp, fp, fn)
            assert metric["precision"] == (tp / (tp + fp) if tp + fp else None)
            assert metric["recall"] == (tp / (tp + fn) if tp + fn else None)
            actual = sum(r["actual_label"] == label for r in rows)
            rejected = sum(r["actual_label"] == label and r["predicted_label"] is None for r in rows)
            assert metric["actual_windows"] == actual
            assert metric["rejected_windows"] == rejected
            assert metric["rejection_fraction"] == (rejected / actual if actual else None)
    for args, status in [([str(executable), "--unknown"], 2),
                         (arguments + ["--minimum-windows-per-class", "21"], 1),
                         (arguments + ["--controls-only"], 1),
                         (arguments + ["--manifest", "duplicate"], 2)]:
        failed = subprocess.run(args, capture_output=True, timeout=120)
        assert failed.returncode == status, failed.stderr.decode()
        assert not failed.stdout, "Failure leaked a provisional receipt"
        assert failed.stderr, "Failure omitted diagnostics"
    for invalid in ("0", "-1", "1.5", "99999999999999999999999999999"):
        failed = subprocess.run(arguments + ["--minimum-windows-per-class", invalid], capture_output=True, timeout=120)
        assert failed.returncode == 2 and not failed.stdout and failed.stderr
    (fixture / "manifest.json").write_text("{}")
    failed = subprocess.run(arguments, capture_output=True, timeout=120)
    assert failed.returncode == 1 and not failed.stdout
print("Native CLI matches canonical two-session synthetic evaluation; exposure totals verified independently; invalid inputs emit no receipt.")
