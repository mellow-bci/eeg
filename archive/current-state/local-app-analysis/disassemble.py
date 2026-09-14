"""Read-only static disassembly of installed M4 CortexService; never attaches."""
import subprocess,shlex,sys
from pathlib import Path
args=['lldb','--batch','-o','target create "/Applications/EmotivApps/EMOTIV Launcher.app/Contents/MacOS/CortexService" --arch arm64']
for spec in sys.argv[2:]: args += ['-o',spec]
r=subprocess.run(['ssh','-o','BatchMode=yes','-o','ConnectTimeout=5','m4',shlex.join(args)],capture_output=True,text=True)
Path(sys.argv[1]).write_text(r.stdout+r.stderr)
print(sys.argv[1],r.returncode,len(r.stdout))
raise SystemExit(r.returncode)
