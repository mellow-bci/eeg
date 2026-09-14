# Native planned trial controls

Implemented in `TrialCueController.swift` and `TrialCaptureView.swift`, under
Calibration. This is a planned research-trial tool, not a qualified session runner. It does not start capture, speech or an experiment automatically.

## Flow

1. Connect and start a recording through the existing acquisition controls.
2. Enter a participant pseudonym and independent session identity. Save the
   session plan before the first trial. The seed, 24 conditions and starting
   numbers are written as a `trial_plan` event in the same recording.
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

The initial cue-control checkpoint passed 83 core tests and compiled all three
native targets.
Those tests validate the underlying evidence/session transitions, not the new
AVSpeech UI driver. Interactive inspection was unavailable because the Mac was
locked. No audio or physiological experiment was run for this change.

Remaining before a qualification acquisition: inspect the rendered controls;
verify speaker route, start/finish/cancel/timeout behavior on hardware; test stop
and disconnection during each phase; qualify plan persistence and rest/break behavior interactively; generate an evidence-linked dataset
manifest; replay its trials through canonical extraction. The session plan must remain independent of observed EEG. Move blocking recording I/O off the
main queue and measure timing under load before relying on cue precision.

## Balanced plan implementation

`EEGTrialPlan` uses a versioned SplitMix64 PRNG, unbiased bounded draws and
Fisher–Yates shuffling. It rejects orders with more than three consecutive trials
of one condition. Each order has 12 neutral and 12 silent-subtraction trials;
starting numbers range from 100 through 999. The complete plan and decimal seed
are retained; this is reproducibility metadata, not cryptographic randomness.
The implementation fails explicitly after 10,000 unsuccessful proposals.

The app saves one plan per recording and validates every trial against the next
planned slot. Interrupted trials consume their slot and remain excluded; they are
not silently replaced. A new recording requires a new plan. The next trial cannot
start before the preceding trial is reviewed or interrupted, then at least ten
seconds have elapsed. Every eighth trial requires sixty seconds. Counting from
review rather than the earlier participant report is a conservative independent
choice. Each subsequent start still requires an audio check and current readiness.
The UI does not restart a plan after a process crash or resume a completed file.

Software tests cover multiple seeds including zero and UInt64.max, balance,
three-trial run limits, unique trial IDs, terminal-state checks, rest boundaries
and exhaustion. This does not validate acoustic timing or participant compliance.

## Trial evidence recovery

`EEGTrialEvidence.recover` reconstructs a snapshot by replaying its allowed
transitions, then compares the complete serialized state with that reconstruction.
A changed acceptance Boolean, cue time, phase, omitted evidence or invalid
transition is rejected. Replayed readiness flags remain historical declarations;
recovery does not independently prove that the participant was ready or heard cues.

`EEGRecordingStore.recoveredTrials` checks recording finalization and the shared
stream schema, source stability, filename binding, sample count at each snapshot,
revision order and unchanged event prefixes. Live writing and recovery use the same
revision invariant. It retains interrupted and unfinished trial states for review;
only the existing `datasetTrial()` gate can yield accepted interval metadata.
A completed recording can contain excluded or unfinished trials.

Regression tests exercise accepted-state round trips, edited cue time, forged
acceptance, numeric Boolean substitution, unfinished recordings and missing
journal revisions. This validates consistency, not cryptographic authenticity:
a complete rewritten history can still be fabricated. Recovery now requires a saved balanced plan, reconstructs it from its seed, and
checks trial identities, order and rest before cue requests. Dataset manifest
generation remains required before the automatic export flow is complete.

Plan recovery rejects missing, duplicate or late plans, seed/content mismatches,
trials out of order, concurrent unfinished trials and insufficient rest before a
cue request. It allows a partial session and retains excluded/unfinished slots;
it does not pad a stopped acquisition to 24 trials. A finalized stream with no
plan is still readable as EEG but cannot pass planned-trial recovery. Tests cover
missing plan, swapped order, seed alteration and both sides of a rest boundary.
These consistency checks do not prove physical independence or participant labels.
