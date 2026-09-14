"""Bounded, read-only access to the pipeline's append-only JSONL recordings."""
import csv
import json
import math
import os
import re
import stat
from pathlib import Path

CHANNELS = ('AF3', 'F7', 'F3', 'FC5', 'T7', 'P7', 'O1', 'O2', 'P8', 'T8', 'FC6', 'F4', 'F8', 'AF4')
MAX_LINE_BYTES = 4 * 1024 * 1024


class RecordingError(ValueError):
    """Invalid recording name, structure or query."""


class RecordingLibrary:
    def __init__(self, directory):
        self.directory = Path(directory).expanduser().resolve(strict=True)
        if not self.directory.is_dir():
            raise RecordingError('Recording directory is not a directory')

    def _open(self, name):
        if not isinstance(name, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,199}\.jsonl', name):
            raise RecordingError('Expected a plain .jsonl recording filename')
        flags = os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0) | getattr(os, 'O_NONBLOCK', 0)
        try:
            fd = os.open(self.directory / name, flags)
        except OSError as exc:
            raise RecordingError('Recording is unavailable') from exc
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            os.close(fd)
            raise RecordingError('Recording must be a regular file')
        return os.fdopen(fd, 'rb')

    def _events(self, file):
        # Freeze the byte boundary so a concurrent writer cannot extend this read.
        remaining = os.fstat(file.fileno()).st_size
        line_number = 0
        while remaining:
            line = file.readline(min(MAX_LINE_BYTES + 1, remaining))
            if not line:
                yield None, 'file_truncated_during_read'
                return
            remaining -= len(line)
            line_number += 1
            if len(line) > MAX_LINE_BYTES:
                raise RecordingError('Recording line exceeds size limit')
            if not line.endswith(b'\n'):
                yield None, 'partial_final_line' if not remaining else 'line_size_limit'
                return
            try:
                event = json.loads(line, parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))
                if not isinstance(event, dict) or not isinstance(event.get('kind'), str):
                    raise ValueError('Missing event kind')
            except (ValueError, UnicodeError, RecursionError):
                yield None, 'malformed_line:%d' % line_number
                continue
            yield event, None

    def inventory(self):
        result = []
        for path in sorted(self.directory.iterdir(), key=lambda p: p.name):
            if path.suffix != '.jsonl' or path.is_symlink() or not path.is_file():
                continue
            try:
                result.append(self.describe(path.name))
            except RecordingError as exc:
                result.append({'name': path.name, 'status': 'unreadable', 'error': str(exc)})
        return result

    def describe(self, name):
        counts = {}
        errors = []
        start = summary = last_kind = None
        stable = calibrated = samples = 0
        with self._open(name) as file:
            size = os.fstat(file.fileno()).st_size
            for event, error in self._events(file):
                if error:
                    if len(errors) < 20:
                        errors.append(error)
                    last_kind = None
                    continue
                last_kind = event['kind']
                counts[last_kind] = counts.get(last_kind, 0) + 1
                if last_kind == 'stream_start' and start is None:
                    start = event
                elif last_kind == 'summary':
                    summary = event
                elif last_kind == 'eeg_adc':
                    samples += 1
                    stable += event.get('transport_stable') is True
                    calibrated += isinstance(event.get('electrodes_microvolts'), dict)
        complete = last_kind == 'summary' and summary is not None and start is not None and not errors
        return {'name': name, 'bytes': size, 'status': 'corrupt' if any(e != 'partial_final_line' for e in errors) else ('complete' if complete else 'incomplete'),
                'complete': complete, 'capture_clean': summary.get('capture_clean') if complete else None,
                'samples': samples, 'stable_samples': stable, 'calibrated_samples': calibrated,
                'events': counts, 'errors': errors, 'start': start, 'summary': summary,
                'physiology_validated': False}

    @staticmethod
    def _query(channels, units):
        if units not in ('adc', 'microvolts'):
            raise RecordingError('units must be adc or microvolts')
        selected = list(CHANNELS) if channels is None else list(channels)
        if not selected or any(c not in CHANNELS for c in selected) or len(set(selected)) != len(selected):
            raise RecordingError('Select unique supported electrode names')
        return selected, 'electrodes_' + units

    def _samples(self, file, selected, field, stable_only):
        for event, error in self._events(file):
            if error:
                raise RecordingError(error)
            if event['kind'] != 'eeg_adc' or (stable_only and event.get('transport_stable') is not True):
                continue
            values = event.get(field)
            # Never silently substitute ADC counts when calibrated voltages are absent.
            if not isinstance(values, dict):
                raise RecordingError('Requested channel units are unavailable')
            if any(not isinstance(values.get(c), (int, float)) or isinstance(values[c], bool)
                   or not math.isfinite(values[c]) for c in selected):
                raise RecordingError('Invalid electrode values')
            metadata = {key: event.get(key) for key in ('stream_index', 'index', 'received_at', 'counter', 'epoch', 'stable_segment', 'continuous')}
            if any(value is not None and (not isinstance(value, (int, float, bool))
                    or not math.isfinite(value)) for value in metadata.values()):
                raise RecordingError('Invalid numeric sample metadata')
            yield {'stream_index': event.get('stream_index', event.get('index')),
                   'received_at': event.get('received_at'), 'counter': event.get('counter'),
                   'epoch': event.get('epoch'), 'stable_segment': event.get('stable_segment'),
                   'transport_stable': event.get('transport_stable') is True,
                   'consumer_eligible': event.get('consumer_eligible') is True,
                   'continuous': event.get('continuous'),
                   'values': {c: values[c] for c in selected}}

    def replay(self, name, offset=0, limit=500, stride=1, channels=None, units='adc', stable_only=False):
        for value, lower, upper in ((offset, 0, 10**12), (limit, 1, 10000), (stride, 1, 100000)):
            if type(value) is not int or not lower <= value <= upper:
                raise RecordingError('Invalid pagination parameter')
        selected, field = self._query(channels, units)
        result = []
        next_offset = None
        with self._open(name) as file:
            for index, sample in enumerate(self._samples(file, selected, field, stable_only)):
                if index < offset or (index - offset) % stride:
                    continue
                if len(result) == limit:
                    next_offset = index
                    break
                result.append(sample)
        return {'name': name, 'channels': selected, 'units': units, 'samples': result,
                'offset': offset, 'next_offset': next_offset, 'stride': stride,
                'stable_only': stable_only, 'downsampling': 'point_selection_no_antialias_filter',
                'voltage_centering': 'none' if units == 'microvolts' else None,
                'physiology_validated': False}

    def export_csv(self, name, output, channels=None, units='adc', stable_only=False):
        selected, field = self._query(channels, units)
        # Caller owns the destination and commits a temp file only after success.
        metadata = ['stream_index', 'received_at', 'counter', 'epoch', 'stable_segment',
                    'transport_stable', 'consumer_eligible', 'continuous']
        writer = csv.writer(output)
        writer.writerow(metadata + ['units'] + selected)
        count = 0
        with self._open(name) as file:
            for sample in self._samples(file, selected, field, stable_only):
                values = [sample[key] for key in metadata]
                if any(value is not None and not isinstance(value, (int, float, bool)) for value in values):
                    raise RecordingError('Invalid numeric sample metadata')
                writer.writerow(values + [units] + [sample['values'][c] for c in selected])
                count += 1
        return {'name': name, 'samples': count, 'channels': selected, 'units': units,
                'stable_only': stable_only, 'physiology_validated': False}
