#!/usr/bin/env python3
"""Offline, bounded-memory recording checks; never production/physiology certification."""
import argparse
import collections
import hashlib
import json
import math
from pathlib import Path


def qualify(path, min_seconds=120, min_stable_seconds=10, expected_hz=128,
            rate_tolerance=0.02, allow_startup_errors=False):
    for value in (min_seconds, min_stable_seconds, expected_hz, rate_tolerance):
        if not math.isfinite(value) or value < 0:
            raise ValueError('Thresholds must be finite and nonnegative')
    if expected_hz == 0:
        raise ValueError('expected_hz must be positive')
    counts = collections.Counter()
    startup = collections.Counter()
    after = collections.Counter()
    epochs = {}
    segments = {}
    ever_ready = False
    last_kind = None
    summary = None
    malformed = []
    digest = hashlib.sha256()
    def issue(name):
        (after if ever_ready else startup)[name] += 1
    with open(path, 'rb') as source:
        for number, line in enumerate(source, 1):
            digest.update(line)
            try:
                row = json.loads(line)
                if not isinstance(row, dict) or not isinstance(row.get('kind'), str):
                    raise ValueError('missing event kind')
            except (ValueError, UnicodeDecodeError):
                if len(malformed) < 20:
                    malformed.append(number)
                counts['malformed'] += 1
                continue
            kind = row['kind']
            counts[kind] += 1
            last_kind = kind
            if kind == 'summary':
                summary = row
            if kind in ('decode_error', 'connection_error', 'transport_interruption', 'fatal_error'):
                issue(kind)
            if kind == 'transport_status':
                if row.get('status') == 'stable':
                    ever_ready = True
                elif row.get('status') == 'recovering':
                    issue('recovery_transition')
            if kind != 'eeg_adc':
                continue
            try:
                epoch = row['epoch']
                timestamp = row['received_at']
                counter = row['counter']
                if not isinstance(epoch, int) or not isinstance(counter, int) or not 0 <= counter < 128:
                    raise ValueError()
                if not isinstance(timestamp, (int, float)) or not math.isfinite(timestamp):
                    raise ValueError()
                state = epochs.setdefault(epoch, {'samples': 0, 'first': timestamp, 'last': timestamp,
                                                   'counter': None, 'first_batch': 0})
                if timestamp < state['last']:
                    issue('clock_reversal')
                if timestamp-state['last'] > 0.5:
                    issue('arrival_gap')
                if state['counter'] is not None and counter != (state['counter']+1) % 128:
                    issue('counter_gap')
                if timestamp == state['first']:
                    state['first_batch'] += 1
                state['samples'] += 1
                state['last'] = timestamp
                state['counter'] = counter
                if row.get('transport_stable') is True:
                    ever_ready = True
                    counts['stable_samples'] += 1
                    if row.get('consumer_eligible') is not True:
                        issue('stable_sample_not_calibrated')
                    segment = row.get('stable_segment')
                    if not isinstance(segment, int):
                        raise ValueError()
                    segment_state = segments.setdefault((epoch, segment), [timestamp, timestamp])
                    segment_state[1] = timestamp
            except (KeyError, TypeError, ValueError):
                issue('invalid_sample')
    epoch_reports = []
    for epoch, state in epochs.items():
        span = state['last']-state['first']
        rate = (state['samples']-state['first_batch'])/span if span > 0 else None
        epoch_reports.append({'epoch': epoch, 'samples': state['samples'], 'arrival_span_seconds': span,
                              'observed_arrival_rate_hz': rate})
    duration = sum(max(0, s['arrival_span_seconds']) for s in epoch_reports)
    stable_duration = sum(max(0, b-a) for a, b in segments.values())
    checks = {
        'valid_jsonl': not counts['malformed'],
        'single_terminal_summary': counts['summary'] == 1 and last_kind == 'summary',
        'has_samples': counts['eeg_adc'] > 0,
        'minimum_duration': duration >= min_seconds,
        'minimum_stable_duration': stable_duration >= min_stable_seconds,
        'no_post_readiness_issues': not after,
        'startup_policy': allow_startup_errors or not startup,
        'single_connection_epoch': len(epochs) == 1,
        'arrival_rate_within_tolerance': bool(epoch_reports) and all(
            e['observed_arrival_rate_hz'] is not None and
            abs(e['observed_arrival_rate_hz']/expected_hz-1) <= rate_tolerance for e in epoch_reports),
        'summary_sample_counts_match': bool(summary) and summary.get('samples') == counts['eeg_adc']
            and summary.get('stable_samples') == counts['stable_samples'],
        'summary_decode_errors_match': bool(summary) and summary.get('decode_errors') == counts['decode_error'],
        'summary_no_fatal_or_connection_failure': bool(summary) and summary.get('fatal_error') is None
            and summary.get('connection_errors') == 0 and summary.get('transport_interruptions') == 0,
    }
    return {'schema': 'eeg.offline-qualification.v1', 'status': 'PASS' if all(checks.values()) else 'FAIL',
            'scope': 'Single-epoch recording transport evidence only; not physiological or production certification',
            'sha256': digest.hexdigest(), 'checks': checks,
            'thresholds': {'min_seconds': min_seconds, 'min_stable_seconds': min_stable_seconds,
                           'expected_hz': expected_hz, 'rate_tolerance': rate_tolerance,
                           'allow_startup_errors': allow_startup_errors},
            'event_counts': dict(counts), 'startup_issues': dict(startup),
            'post_readiness_issues': dict(after), 'malformed_line_examples': malformed,
            'arrival_span_seconds': duration, 'stable_arrival_span_seconds': stable_duration,
            'epochs': epoch_reports, 'production_certified': False, 'physiology_validated': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('recording', type=Path)
    parser.add_argument('--min-seconds', type=float, default=120)
    parser.add_argument('--min-stable-seconds', type=float, default=10)
    parser.add_argument('--expected-hz', type=float, default=128)
    parser.add_argument('--rate-tolerance', type=float, default=.02)
    parser.add_argument('--allow-startup-errors', action='store_true')
    args = parser.parse_args()
    try:
        result = qualify(args.recording, args.min_seconds, args.min_stable_seconds,
                         args.expected_hz, args.rate_tolerance, args.allow_startup_errors)
    except (OSError, ValueError) as error:
        parser.exit(2, str(error)+'\n')
    print(json.dumps(result, indent=2, allow_nan=False))
    return 0 if result['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
