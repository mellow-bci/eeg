# Production release gates

**NOT RELEASED.** This repository documents working, empirically validated acquisition and current hardening; it is not a production certification.

| Gate | Current evidence | Remaining acceptance |
|---|---|---|
| Decoder correctness | Two same-sample Cortex comparisons; all stable samples match | Maintain regression fixtures and supported-config restrictions |
| Startup behavior | Errors retained and excluded by stable gate | Explain/qualify startup behavior under standalone and shared connections |
| Reconnection | Three deliberate cycles recover in ~2 s | Unexpected power loss, Bluetooth off/on, sleep/wake and long outage tests |
| Duration/resources | Three-minute run has no post-stability issues; file budget exists | Define target session duration, run extended standalone soak, measure RSS/latency/backlog |
| Failure handling | Storage, callback, silence, lease and SIGTERM tests | Hardware/process termination and disk-failure qualification on deployment host |
| Consumer delivery | Bounded asynchronous FIFO, deep copies, explicit overflow/age/callback/shutdown failures; deterministic worker tests | Qualify under sustained hardware load; separate-process isolation if arbitrary or untrusted callbacks must be forcibly terminated |
| Contact quality | Raw CQ agrees with Cortex | Validate class normalization/state behavior across good/poor contacts |
| Standalone operation | Earlier direct acquisition works; current comparison shared Cortex connection | Explicit recorded lifecycle with Cortex disconnected and no vendor-stream dependence |
| Installation | Pinned environment/runbook | Clean-host repeatability, service lifecycle, permissions onboarding and support matrix |
| Persistence | Private exclusive JSONL, budget, flush/final fsync | Rotation/retention, crash recovery and operational monitoring policy |
| Packaging | Private source/evidence repository | Versioned reproducible deployment artifact and release sign-off |

The root-owned Cortex service on the comparison Mac cannot be stopped by the current SSH account without a password. A user-visible disconnect in EMOTIV Launcher was requested for standalone testing; it was not completed before this documentation snapshot. Do not substitute a concurrently connected reader for that test.

No downstream intent model, application action, medical decision or Apple HID integration is enabled. Those have separate user-calibration and evaluation requirements beyond raw acquisition.
