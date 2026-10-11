# Offline timestamp and ordinary motion continuation

Installed M4 CortexService arm64 SHA256 cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a reconfirmed 2026-10-11. bodies.txt is static LLDB disassembly, no execution/attach or model asset extraction.

## Offline path

processOfflineData 0x101073848 checks start field +0x228 >0; otherwise error17. With pending +0x238, it scans forward for numeric type16, copies each candidate into a singleton and calls addFirstTimestamp at 0x101073a38. Successful candidate index is retained at 0x101073abc; scan stops after success. Prefix through that candidate is removed at 0x101073ba8, remainder timestamped at 0x101073bbc with false control, and anchor prepended. No candidate gives error21. Pending clears at 0x101073c40. Subsequent calls directly tail-call addTimeStamp with true control at 0x101073d28, forcing nominal rate. No live sync or hardware-offset call occurs here.

ReferenceOfflineTimestampWorkflow composes the existing clock anchor and EEG arithmetic for explicitly EEG-only input. Initial elapsed is zero, so nominal rate also applies to the initial remainder. It preserves original input by returning input indices and derived timestamps. Mixed packets fail explicitly; it does not pretend to implement their full offline route. Caller supplies configuration, start time and prior pre-offset time. Atomic errors, finite/resource bounds and nonnegative clocks are independent support policies. Empty unanchored input fails; empty established input changes nothing. Other internal constructor/reset/error encoding remains outside this subset.

## Ordinary motion clock

processMotion 0x101075198 distinguishes modes6/9, mode10 and ordinary modes. Ordinary first-packet flag +0x220 is cleared at 0x101075214. First time comes from positive offline field or getCurrEpochSteady at 0x101075228. Later packets use own previous counter +0x210, common counter modulus and FMA(1/rate,distance,motionTime) at 0x1010752e0. Round at 0x1010752ec, store unrounded motion time and counter at 0x1010752f4/fc. ReferenceOrdinaryMotionClock implements this ordinary branch with explicitly supplied first clock observation, separate from EEG time. Modes6/9/10 are explicitly excluded. This is timestamp arithmetic, not physical motion decoding.

## Correction to prior reset/history backlog

Complete removeBadCounterSample in ../timestamp-clock-continuation-20261011/outer-reset.txt, 0x101074708..4dbc, checks first type16 whose absolute timestamp deviation exceeds +0x1b8. Boundary is strict >. At 0x10107478c..79c it sets ready flag false, reset-origin flag true, pending EEG anchor true and first-motion true. The history iteration 0x101074870..49e0 formats diagnostic strings; it does not reconstruct, delete or repair stored samples. It returns error22 at 0x101074c60..d48. ReferenceTimestampResetGate reports first invalid index/error22 and reanchor requirement without altering observations. Full parent warmup/reset state integration remains pending; do not keep a nonexistent history-repair algorithm on the queue.

## Validation

Five authored tests cover offline first-anchor retention, no live offset, counter wrap and synthetic-history distinction; partition equivalence; invalid/unsupported input and failed-anchor atomicity; independent motion anchor/unrounded progression; strict reset threshold/first violation/non-EEG exclusion. The integrated reference suite passed 327 tests, two skipped, zero failures (reference-tests.log). Skips are optional native replay export and missing matched Cortex profile/output fixture. These are software tests, not same-input Cortex oracle comparison or physiological qualification.

Remaining: full mixed-packet offline and special-mode motion branches, parent live warmup/reset integration, upstream positive external clock argument, loaded settings and real reference timing. No vendor assets required for this arithmetic.

## Anchor-field correction

Anchor address validation: addFirstTimestamp initializes x22=count*0x3a0−0x390, reads type, then subtracts 0x3a0 before loading [base+x22+0x39c]. For selected index i, x22=i*0x3a0−0x390, hence the load is selected+0xc, the ordinary counter. The intermediate hypothesis of a distinct anchor field was rejected after tracing register updates. No extra packet field is required. The original selected.counter implementation is retained.

Additional captures show mode7 EPOC X dispatch to convert_pkgs_EpocPlusMode. Package conversion and constructor were inspected while checking field origin; no distinct anchor-counter field is established or needed.
