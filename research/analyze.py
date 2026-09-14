"""Analyze transport framing; never labels unknown bytes as EEG samples."""
import argparse
import json
from collections import defaultdict
from pathlib import Path

def analyze(report):
    groups = defaultdict(list)
    for packet in report['packets']:
        groups[(packet['uuid'], len(bytes.fromhex(packet['hex'])))].append(packet)
    result = {'decoded': False, 'eeg_sample_rate': None, 'groups': []}
    for (uuid, size), packets in sorted(groups.items()):
        payloads = [bytes.fromhex(p['hex']) for p in packets]
        elapsed = packets[-1]['t']-packets[0]['t']
        result['groups'].append({
            'uuid': uuid, 'payload_bytes': size, 'notifications': len(packets),
            'notifications_per_second': (len(packets)-1)/elapsed if elapsed > 0 else None,
            'constant_byte_positions': {str(i): payloads[0][i] for i in range(size)
                                        if len(payloads)>1 and len({b[i] for b in payloads}) == 1}})
    return result

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('capture')
    p.add_argument('--output')
    args = p.parse_args()
    result = json.dumps(analyze(json.loads(Path(args.capture).read_text())), indent=2)+'\n'
    if args.output:
        Path(args.output).write_text(result)
    print(result)
