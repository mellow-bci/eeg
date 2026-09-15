# Sequential detector timing gate

The native `EEGExperimentalDetector` and Python reference `Detector` reject
negative, nonfinite or non-increasing window bounds. For the current session and
continuity identity, a new window starting before the retained previous window's
end returns `overlapping_or_reordered_window`. It clears pending persistence and
returns no experimental candidate, evidence start or command. A later valid window
must begin a new persistence streak.

Previously the absolute 0.05-second adjacency tolerance could admit a window
starting slightly before the previous end. That tolerance now applies only after
the explicit overlap rejection. Equal endpoints and small positive separations
are accepted; a forward separation over 0.05 seconds restarts persistence. This
supports the canonical last-sample receipt-time boundary convention. The tolerance
is an independent engineering choice, not a recovered Cortex parameter or a
physiological timing guarantee.

Changing session/continuity or explicitly resetting starts a new sequence. Neutral,
artifact, ambiguous, out-of-distribution and numerical-error outcomes clear the
candidate streak. Python reference reset now also clears retained timing and
identity state, matching native behavior. This gate is not a permanent replay-ID
registry: after a reset, provenance and ordering must still be supplied by the
canonical loader/acquisition service. Dataset evaluation also independently rejects
overlapping intervals within each session.

Native live and replay inference call this same detector. Negative or overlapping
inputs are not corrected, shifted, interpolated or stored as new raw measurements.
The profile's learned parameters and source files are unchanged. Proposal status
remains `no_reliable_command`, command stays null, and system control is false even
for persistent experimental candidates.

`native-labeled-evaluation-8` receipts describe the tightened timing rule. Earlier
receipts must not be attributed to the new gate. This is a behavior change in
validation, not a claim that an old profile became physiologically qualified.

## Verification

```sh
swift test --package-path apple --filter 'ExperimentalDetectorTests|LabeledEvaluationTests'
python -m unittest tests.test_mental_processing
swift test --package-path apple --filter 'ReplayInferenceTests|ShadowVerificationTests'
```

Synthetic tests cover a 0.01-second overlap, a larger overlap, reordered/repeated
window bounds, negative start, recovery after rejection and a valid 1/128-second
separation. Existing exact adjacency, session/continuity reset, neutral, artifact,
outlier and numerical failure behavior remains covered. Test success does not
prove hardware timing, independent trials or mental-command accuracy.

Checkpoint 2026-09-15: 12 selected native detector/evaluation tests, 17 Python
mental-processing tests and 11 native replay/shadow verification tests passed.
macOS, iOS and visionOS builds succeeded. No live headset recording, cue playback
or UI interaction was performed for this gate change.
# Imported sample-index boundaries

2026-09-15. Native recording validation accepts nonnegative `Int` sample indices,
including `Int.max`. Inspection found three downstream checks evaluating
`previous.index + 1`, which can trap on an otherwise parseable imported value.
The shared `EEGSample.followsIndexAndCounter` now compares a known-positive
successor minus one with a nonnegative predecessor, and checks both counter
ranges before modular addition. It is an adjacency predicate only; it does not
claim timing, transport, signal or physiological validity.

Analysis-window assembly, spectrum validation and nominal export planning use
the same predicate. `Int.max - 1 → Int.max` can be adjacent, but `Int.max → 0`
cannot be represented as continuous. Counter `127 → 0` remains valid when indices
advance normally. Raw decoding and stored sample values are unchanged.

`SampleSequenceTests` checks integer/counter extrema, direct spectrum rejection,
and an actual finalized two-sample native recording containing indices
`Int.max, 0`. Canonical analysis retains both indices and reports
`index_or_counter_gap`; nominal planning retains both samples in separate runs.
The original file bytes remain identical. No process crash was induced to prove
the prior arithmetic issue; the new boundary cases exercise the corrected path.

Twenty-five selected tests passed. All three native builds and the independent
compiled-source identity oracle also passed:

```sh
swift test --package-path apple --filter 'SampleSequenceTests|AnalysisWindowTests|SpectrumTests|DecoderTests|EDFNominalPlanTests'
```

This is malformed-input handling, not evidence of physically observed counter
loss or native headset qualification.
