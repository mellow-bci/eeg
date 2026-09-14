"""Generate reproducible audio-cue training plans; never execute cues or hardware.

Each generated manifest is a proposed experiment, not a physiological validation
result. Record a distinct session for evaluation; this generator assigns no splits.
"""
import argparse
import json
import os
import random
from pathlib import Path

SCHEMA_VERSION = 'eeg.calibration.protocol.v1'
PROTOCOLS = {
    'eyes_open_closed': {
        'labels': ('eyes_open', 'eyes_closed'),
        'instructions': (
            'Sit comfortably and remain still. Follow the spoken eyes-open or eyes-closed cue. '
            'Keep your eyes comfortably open during initial rest. A final spoken cue tells you '
            'to open your eyes. Stop whenever uncomfortable. These are training labels, '
            'not proof of neural intent or a validated classifier.'
        ),
        'cues': {'eyes_open': 'Open your eyes. Remain still until the next spoken cue.',
                 'eyes_closed': 'Close your eyes gently. The next spoken cue will tell you when to open them.'},
        'finish': 'The experiment is finished. Open your eyes and relax.'
    },
    'blink_neutral': {
        'labels': ('deliberate_blink', 'neutral'),
        'instructions': (
            'Sit comfortably and remain still. During a deliberate-blink block, make a few '
            'comfortable deliberate blinks. During neutral blocks, relax and blink naturally. '
            'Do not squeeze your eyes or move your jaw. Stop whenever uncomfortable. '
            'Blink activity is an ocular artifact task, not evidence of decoded neural intent.'
        ),
        'cues': {'deliberate_blink': 'Make a few comfortable deliberate blinks until the next spoken cue.',
                 'neutral': 'Relax. Look comfortably ahead and blink naturally until the next spoken cue.'},
        'finish': 'The experiment is finished. Relax.'
    }
}


def generate_protocol(protocol, seed, trial_count=12, block_seconds=10, initial_rest_seconds=10):
    """Return a balanced shuffled schedule with exact planned monotonic offsets.

    No train/test assignment or physiological metrics are produced. Audio latency
    and actual event timestamps must be captured later by a separate executor.
    """
    if protocol not in PROTOCOLS:
        raise ValueError('Unsupported protocol: choose eyes_open_closed or blink_neutral')
    if type(seed) is not int or not 0 <= seed <= 2**64 - 1:
        raise ValueError('seed must be an unsigned 64-bit integer')
    if type(trial_count) is not int or not 2 <= trial_count <= 1000 or trial_count % 2:
        raise ValueError('trial_count must be even, between 2 and 1000')
    for label, value in (('block_seconds', block_seconds), ('initial_rest_seconds', initial_rest_seconds)):
        if type(value) is not int or not 1 <= value <= 3600:
            raise ValueError(label + ' must be an integer between 1 and 3600')
    definition = PROTOCOLS[protocol]
    order = list(definition['labels']) * (trial_count // 2)
    random.Random(seed).shuffle(order)
    events = [{
        'event_id': 'initial-rest', 'trial_id': None, 'offset_seconds': 0,
        'duration_seconds': initial_rest_seconds, 'label': 'initial_rest',
        'cue_text': 'The experiment will begin shortly. Sit still, keep your eyes comfortably open and relax.'
    }]
    for index, label in enumerate(order):
        trial_id = 'trial-%03d' % (index + 1)
        events.append({
            'event_id': trial_id, 'trial_id': trial_id,
            'offset_seconds': initial_rest_seconds + index * block_seconds,
            'duration_seconds': block_seconds, 'label': label,
            'cue_text': definition['cues'][label]
        })
    duration = initial_rest_seconds + trial_count * block_seconds
    events.append({'event_id': 'finish', 'trial_id': None, 'offset_seconds': duration,
                   'duration_seconds': 0, 'label': 'finished', 'cue_text': definition['finish']})
    return {
        'schema_version': SCHEMA_VERSION,
        'protocol': protocol, 'seed': seed,
        'experiment_type': 'training_experiment', 'validation_result': False,
        'randomization': 'balanced_labels_python_random_MT19937_shuffle',
        'initial_rest_seconds': initial_rest_seconds, 'block_seconds': block_seconds,
        'trial_count': trial_count, 'planned_duration_seconds': duration,
        'instructions': definition['instructions'], 'events': events,
        'execution': {'mode': 'audio_cues', 'executed': False,
                      'timing': 'planned_offsets_only_actual_onsets_must_be_recorded'},
        'evaluation_policy': 'Use separate recorded sessions for evaluation; no train/test split is assigned here.'
    }


def write_manifest(manifest, output):
    """Write a new private JSON file; existing files and symlinks are never replaced."""
    data = (json.dumps(manifest, indent=2, allow_nan=False) + '\n').encode('utf-8')
    path = Path(output)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0)
    descriptor = os.open(path, flags, 0o600)
    with os.fdopen(descriptor, 'wb') as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    return path


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    generate = commands.add_parser('generate', help='Write an unexecuted audio-cue training plan')
    generate.add_argument('--protocol', choices=sorted(PROTOCOLS), required=True)
    generate.add_argument('--seed', type=int, required=True)
    generate.add_argument('--output', type=Path, required=True)
    generate.add_argument('--trials', type=int, default=12)
    generate.add_argument('--block-seconds', type=int, default=10)
    generate.add_argument('--initial-rest-seconds', type=int, default=10)
    args = parser.parse_args(argv)
    try:
        manifest = generate_protocol(args.protocol, args.seed, args.trials,
                                     args.block_seconds, args.initial_rest_seconds)
        output = write_manifest(manifest, args.output)
    except (ValueError, OSError) as exc:
        parser.exit(2, 'Cannot create protocol: %s\n' % exc)
    print(str(output))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
