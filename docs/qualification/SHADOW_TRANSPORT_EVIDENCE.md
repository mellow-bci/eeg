# Shadow replay must retain transport evidence

Date: 2026-09-15. Scope: native recorded-live-output verification, not raw
acquisition or physiological performance.

## Findings from actual source and failing tests

`EEGShadowVerification.run` previously skipped global events without the selected
`shadow_run_id`. It also cached metadata without considering whether the run was
active and initialized replay using a manufactured stable-transport event.
Consequently, matching sample/output rows could pass despite contradictory or
missing recorded lifecycle evidence.

Two synthetic regression tests demonstrated the issue before the fix:

- Eight failed rejection assertions: transport recovery, decoder failure,
  connection failure and changed metadata inserted either immediately after
  start or immediately before stop were silently ignored.
- Six failed rejection assertions: absent/recovering initial transport and
  decoder/connection faults before start did not prevent verification.

Fixtures use the actual queued recording writer, canonical sample contract and
live inference consumer. They then insert explicit events in temporary recording
copies. They do not simulate a participant or assert authentic hardware faults.

## Current behavior

The verifier requires a recorded stable transport event before the selected run
starts. Recovery, decoder failure and connection failure clear that evidence;
a later recorded stable event can establish it again before a new start.
The original event is passed into the canonical assembler. No replacement
stability observation is invented.

During an active run, global metadata, transport-status, decoder-error or
connection-error events reject verification with `invalidRun`. This is the
supported native host ordering: `AcquisitionModel.setTransport` stops shadow
inference before recording a transport change; metadata is supplied to its
consumer at start. An unexplained active-run transition is not silently treated
as another supported pipeline. Future formats supporting such transitions would
need an explicit contract and qualification.

Events after the selected stop do not retroactively alter that completed run.
Tests preserve this positive case for each inserted event and verify that an
explicit return to stable transport before start permits replay again.

Historical recordings lacking required startup transport evidence now fail this
verification gate. Their original samples remain readable through normal replay;
no metadata is backfilled and no acquisition bytes are rewritten by verification.
This is distinct from absent implementation-source identity, which remains an
explicit unavailable field in a structurally valid run.

## Reproduction

Local result: all six `ShadowVerificationTests` passed with zero failures in
3.857 seconds. macOS, iOS simulator and visionOS simulator builds succeeded.
No headset capture, audio cue or participant experiment was performed.

```sh
swift test --package-path apple --filter ShadowVerificationTests
./apple/build-native.sh all
```

The fix changes verification, not the decoder, live classifier parameters or
system-action policy. A replay match remains a software consistency observation,
not evidence of intent accuracy, source authenticity or physical qualification.

## Single active run ordering

A subsequent regression test exposed another issue in both catalog discovery and
direct verification: each ignored conflicting events belonging to a different run
ID. Six injected histories produced twelve failed rejection assertions across the
two entry points. They included starts nested before/inside the selected run,
stops for an inactive run and inference assigned to an inactive run.

Both entry points now use the same bounded-state `RunOrder` validator. Start
requires no active run; inference and stop must name the active run; stop clears
it. Run identifiers must be present, nonblank and bounded. The validator does not
duplicate sample assembly or classification. Catalog discovery still checks
unique run IDs and metadata; listing is not full numeric verification.

Complete sequential runs before or after the selected run remain supported.
Tests verify two catalog entries and an unchanged match for the selected run.
The other run has no windows and cannot claim a complete match. An unfinished
final run remains inspectable as incomplete; no artificial stop is inserted.

All seven shadow tests passed with zero failures in 4.429 seconds after this
change. This is synthetic event-ordering evidence, not live-device qualification.
