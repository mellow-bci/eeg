#!/usr/bin/env python3
"""Independent framing oracle and relocation/change checks for the build tool."""
import hashlib
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def digest(root, paths):
    h = hashlib.sha256()
    fields = [b'eeg.core-source.v1']
    for path in sorted(paths, key=lambda p: p.relative_to(root).as_posix()):
        fields.extend([path.relative_to(root).as_posix().encode(), path.read_bytes()])
    for field in fields:
        h.update(len(field).to_bytes(8, 'big'))
        h.update(field)
    return h.hexdigest()


def run(tool, root, names):
    paths = [root / name for name in names]
    output = root / 'generated.swift'
    subprocess.run([str(tool), str(root), str(output), *map(str, reversed(paths))], check=True)
    actual = re.search(r'sha256 = "([a-f0-9]{64})"', output.read_text()).group(1)
    assert actual == digest(root, paths), 'Independent digest mismatch'
    assert f'inputFileCount = {len(paths)}' in output.read_text()
    return actual


def main():
    tool = Path(sys.argv[1]).resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix='eeg-source-identity-') as temporary:
        roots = [Path(temporary) / 'one', Path(temporary) / 'relocated']
        for root in roots:
            (root / 'Sources').mkdir(parents=True)
            (root / 'Sources/a.swift').write_bytes(b'let value = 1\n')
            (root / 'Package.swift').write_bytes(b'package\x00content')
        names = ['Sources/a.swift', 'Package.swift']
        original = run(tool, roots[0], names)
        assert original == run(tool, roots[0], names), 'Repeated output changed'
        assert original == run(tool, roots[1], names), 'Absolute path leaked into digest'
        (roots[0] / names[0]).write_bytes(b'let value = 2\n')
        assert original != run(tool, roots[0], names), 'Content change not detected'
        (roots[1] / names[0]).rename(roots[1] / 'Sources/b.swift')
        assert original != run(tool, roots[1], ['Sources/b.swift', 'Package.swift']), 'Rename not detected'
    package = Path(__file__).resolve().parents[1] / 'apple'
    paths = list((package / 'Sources/EEGCore').rglob('*.swift')) + [
        package / 'Package.swift', package / 'Plugins/EEGSourceIdentityPlugin/plugin.swift',
        package / 'Tools/EEGSourceIdentityTool/main.swift']
    # Compare the actual plugin output, not only synthetic inputs to the helper.
    outputs = list((package / '.build/plugins/outputs').rglob('EEGSourceIdentity.swift'))
    assert outputs, 'Build EEGCore before checking generated identity'
    for output in outputs:
        assert f'sha256 = "{digest(package, paths)}"' in output.read_text(), f'Stale or incomplete fingerprint: {output}'
        assert f'inputFileCount = {len(paths)}' in output.read_text()
    print('Source identity: independent oracle, relocation, repeat, content, rename and compiled-input checks passed')


if __name__ == '__main__':
    main()
