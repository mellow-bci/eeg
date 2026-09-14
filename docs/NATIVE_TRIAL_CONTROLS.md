# Native individual trial controls

Implemented in `TrialCueController.swift` and `TrialCaptureView.swift`, under
Calibration. This is an individual research-trial tool, not a complete qualified
session runner. It does not start capture, speech or an experiment automatically.

## Flow

1. Connect and start a recording through the existing acquisition controls.
2. Enter a participant pseudonym, independent session identity, condition and
   starting number. Manual choice is suitable for checking the controls, not a
   balanced prospective qualification study.
3. Play the audio check. Its completion enables the heard-check declaration.
   Explicitly confirm current readiness and hearing the check before Start trial.
4. Instruction start/completion callbacks commit evidence in the original recording.
   Completion starts a 20-second condition period. The shared trial contract retains
   the +5 to +17 second scoring interval.
5. A spoken end cue precedes participant report and operator review. Uncertain,
   missed or unattempted reports cannot be accepted. Behavioral observation remains
   unknown; this UI does not acquire camera, eye tracking or motion measurements.
6. Stop, loss of transport or recording failure invalidates the unfinished trial.
   Stop attempts a spoken rest instruction; visible status remains necessary when
   audio cannot be played. A crash cannot guarantee an end instruction.

Every start consumes its readiness/heard declarations. A new audio check is
required for the next trial. This conservative per-trial policy is our design,
not a recovered vendor rule. Recording must remain active through review.

## Timing and failure behavior

Apple's [AVSpeechSynthesizerDelegate](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizerdelegate)
provides utterance start, finish, pause and cancellation notifications. We record
main-queue handling times on the acquisition receipt clock. These are callback
observations, not measured acoustic onset/offset or proof of audibility.

A 100 ms timer requests the end cue; delivery more than 500 ms beyond the planned
end invalidates the trial. Speech missing a completion callback for 30 seconds
also stops the trial. Both tolerances are independent operational choices, not
scientifically validated or recovered Cortex parameters. Pause/cancel invalidates
the trial. Speech route/volume and callback-to-acoustic timing remain unqualified.
No speech recognition, vendor runtime or online language model is used.

## Evidence and remaining work

The 83 core tests pass and macOS/iOS/visionOS targets compile with these controls.
Those tests validate the underlying evidence/session transitions, not the new
AVSpeech UI driver. Interactive inspection was unavailable because the Mac was
locked. No audio or physiological experiment was run for this change.

Remaining before a qualification acquisition: inspect the rendered controls;
verify speaker route, start/finish/cancel/timeout behavior on hardware; test stop
and disconnection during each phase; persist a balanced precommitted session
plan/seed and enforce rest/break intervals; generate an evidence-linked dataset
manifest; replay its trials through canonical extraction. Manual trial choice
must not stand in for that session protocol. Move blocking recording I/O off the
main queue and measure timing under load before relying on cue precision.
