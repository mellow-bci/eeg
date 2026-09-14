# Bounded installed-software reference trace

Read-only static arm64 disassembly of the installed M4 CortexService, matched to the recorded SHA256. No process attach, executable patch, license modification, bundle redistribution or model-asset extraction occurred.

`manifest.json` lists the 12 selected ranges, symbol names, addresses, trace hashes and confidence caveat about adjacent unnamed compiler helpers. `all-routines.txt` preserves the original LLDB output; individual files split it by command. `scoring-coefficients.txt` reads only 32 static bytes addressed directly by the selected low-pass setup routine.

See [the interpretation and unresolved parameters](../../docs/MENTAL_REFERENCE_TRACE.md). Names alone do not establish a full EEG algorithm, and an observed body does not establish runtime invocation, parameter values or behavioral parity.

Reproduction uses the existing read-only helper:

```sh
python3 archive/current-state/local-app-analysis/disassemble.py /tmp/mental-body.txt \
  'disassemble --start-address 0x100b1de80 --end-address 0x100b1e8e0'
```

First verify the installed executable hash matches `manifest.json`. Use the manifest ranges for the other commands. The helper creates an LLDB target from the installed executable and does not run or attach to Cortex.
