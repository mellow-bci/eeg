#!/usr/bin/env python3
"""Render the roadmap table from the canonical inventory; check reference existence.

Structural consistency is not scientific validation or proof of vendor parity.
"""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BEGIN = '<!-- BEGIN GENERATED CAPABILITY MATRIX -->'
END = '<!-- END GENERATED CAPABILITY MATRIX -->'


def reference(path):
    resolved = (ROOT / path).resolve()
    if ROOT not in resolved.parents or not resolved.is_file():
        raise ValueError('Missing or out-of-repository evidence: ' + path)
    return resolved


def render(inventory):
    if inventory['schema_version'] != 'eeg.capability-matrix.v1':
        raise ValueError('Unsupported inventory schema')
    ids = set()
    line_counts = {}
    def line_count(path):
        if path not in line_counts:
            line_counts[path] = len(reference(path).read_text().splitlines())
        return line_counts[path]
    source = inventory['source_inventory']
    if line_count(source['path']) != source['lines']:
        raise ValueError('Source inventory line count changed')
    rows = ['| Capability / flow | Actual Cortex symbol evidence | Body evidence / unresolved dependency | Present implementation | Independent canonical component / target | Concrete validation gate | Status enum and covered subset | Delivery notes |',
            '|---|---|---|---|---|---|---|---|']
    for item in inventory['capabilities']:
        if item['id'] in ids or item['status'] not in inventory['status_enum']:
            raise ValueError('Duplicate capability ID or invalid status: ' + item['id'])
        ids.add(item['id'])
        for ref in item['symbol_evidence']['references']:
            if type(ref['line']) is not int or not 1 <= ref['line'] <= line_count(ref['path']):
                raise ValueError('Out-of-range evidence line: ' + item['id'])
        for path in item.get('software_evidence', []):
            reference(path)
        cells = [item['capability'], item['symbol_evidence']['readable_names_and_links'],
                 item['body_evidence'] + ' Missing: ' + item['missing_parameters_assets_dependencies'],
                 item['current_implementation'], item['target_component'], item['acceptance_gate'],
                 '**' + item['status'] + '** — ' + item['status_scope'], item['delivery_notes']]
        rows.append('| ' + ' | '.join(cell.replace('|', '&#124;').replace('\n', ' ') for cell in cells) + ' |')
    return '\n'.join(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='fail if the checked-in table is stale')
    args = parser.parse_args()
    inventory = json.loads((ROOT / 'capability-matrix.json').read_text())
    table = render(inventory)
    path = ROOT / 'docs/PARITY_ROADMAP.md'
    old = path.read_text()
    if old.count(BEGIN) != 1 or old.count(END) != 1:
        raise ValueError('Expected exactly one generated table region')
    before, rest = old.split(BEGIN)
    _, after = rest.split(END)
    updated = before + BEGIN + '\n' + table + '\n' + END + after
    if args.check:
        if updated != old:
            raise SystemExit('Roadmap table is stale: run python tools/render_capability_matrix.py')
        print('Capability table matches canonical inventory; structured evidence files and symbol lines exist. No semantic qualification implied.')
    else:
        path.write_text(updated)


if __name__ == '__main__':
    main()
