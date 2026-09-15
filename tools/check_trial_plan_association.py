#!/usr/bin/env python3
"""Independent exhaustive v1 schedule count fixture; no EEG or vendor runtime."""
import itertools
import json


def count_schedules():
    counts = [0] * 13
    for indices in itertools.combinations(range(24), 12):
        task = sum(1 << index for index in indices)
        neutral = ((1 << 24) - 1) ^ task
        # Bitwise rejection of any four consecutive equal labels.
        if any(bits & (bits >> 1) & (bits >> 2) & (bits >> 3)
               for bits in (task, neutral)):
            continue
        counts[bin(task & ((1 << 12) - 1)).count("1")] += 1
    return counts


if __name__ == "__main__":
    actual = count_schedules()
    expected = [0, 0, 0, 380, 21281, 169490, 323680, 169490, 21281, 380, 0, 0, 0]
    assert actual == expected, actual
    print(json.dumps({"fixture": "candidate_outcome_at_first_12_positions",
                      "schedule_counts_by_task_candidate_trials": actual,
                      "admissible_schedules": sum(actual),
                      "qualification": "synthetic combinatorial check only"}, indent=2))
