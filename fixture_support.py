"""Resolve private hardware fixtures explicitly; never silently use synthetic EEG."""
import os, unittest
from pathlib import Path

def fixture_path(name):
    root=Path(os.environ.get('CHORUS_EEG_FIXTURES',Path(__file__).parent/'archive/current-state'))
    path=root/name
    if not path.is_file():
        raise unittest.SkipTest('Private hardware fixture unavailable: '+name+'; set CHORUS_EEG_FIXTURES')
    return path
