"""Build the macOS offline reference reader using the active pyarrow environment."""
import argparse, subprocess, sys
from pathlib import Path
import pyarrow
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',required=True);a=p.parse_args()
if sys.platform!='darwin':raise SystemExit('This helper currently requires macOS CommonCrypto/Xcode.')
out=Path(a.output).resolve()
if out.exists():raise SystemExit('Refusing to overwrite existing output')
out.parent.mkdir(parents=True,exist_ok=True)
lib=Path(pyarrow.__file__).parent
candidates=[]
for name in ('parquet','arrow'):
 found=sorted(lib.glob('lib'+name+'.[0-9]*.dylib'))
 if len(found)!=1:raise SystemExit('Expected one pyarrow-provided lib'+name+' dylib')
 candidates.append(str(found[0]))
subprocess.run(['clang++','-std=c++17','-Wno-deprecated-declarations','-I'+str(lib/'include'),str(Path(__file__).with_name('read_record.cpp')),*candidates,'-Wl,-rpath,'+str(lib),'-o',str(out)],check=True)
print(out)
