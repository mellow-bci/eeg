# Descriptive signal experiments and algorithms

These experiments show signal responsiveness and preserve analysis code. They do
not establish a usable BCI classifier, infer thoughts or diagnose physiology.

## Spoken eye/blink protocol

`research/audible_eye_test.py` calls the existing Pipeline/live path. It waits up
to 60 seconds for stable transport before giving cues. The participant confirmed
that the Mac audio check was audible. `/usr/bin/say` plays each cue; requested
playback, pre-process onset and process completion are logged separately.

Eye protocol: open 20 s, closed 30 s, open 20 s, closed 30 s, open 20 s.
Blink protocol: baseline 20 s, six “blink twice” cues with 12-second intervals,
then 10-second rest. Spoken durations are additional to phase timing as the
implemented script measures phase intervals after playback completion.

A task end, changed epoch or loss of stability aborts the experiment; abort speech
asks the user to open their eyes. Sidecar markers represent software timing, not
measured eyelid motion or verified participant compliance.

## Blink comparison

For each blink cue, `analyze_blinks.py` takes `[t-4,t)` and `[t,t+4)` windows.
Each requires at least 256 samples, stable/continuous flags, one epoch and
consecutive stream indices. For each channel it applies SciPy linear detrend,
then computes `RMS = sqrt(mean(x*x))` and peak-to-peak `max(x)-min(x)`.
Post/pre RMS ratio is descriptive, with a tiny denominator floor in console
reporting. There is no learned threshold or classifier.

Observed six AF4 ratios: **4.41, 5.22, 4.59, 6.24, 5.46, 4.33**.
AF3: **2.68, 1.24, 3.60, 18.05, 3.06, 3.37**. O1/O2 ratios were about 1.42–2.31,
smaller than AF4 in each trial. This is consistent with cue-associated frontal
ocular artifacts. Actual blink count/timing was not independently measured;
there was no sham/silent cue control and speech itself may contribute responses.

## Eye-phase power

`compare_eye_phases.py` uses adjacent markers, discards 5 seconds after the first
and 3 seconds before the next, and keeps at most a central 20-second window.
It requires one epoch, stable/continuous samples, consecutive indices and at
least 1024 samples. Welch PSD: `fs=128`, `nperseg=512`, linear detrend. Band power
is the sum of PSD bins in `[low,high)` times frequency-bin width. It reports
8–13 Hz power, 1–40 Hz power, their ratio and ADC-rail fraction.

The eye recording did not show a consistent posterior alpha increase on closing
the eyes. Outcome: **inconclusive**, not a failed hardware proof or successful
brain-state decoder.

## General signal inspection

`analyze_signal.py` selects the longest segment of stable/continuous EEG with
one epoch. It reports ADC min/max, fraction at 0 or 65535, unchanged adjacent
values, uncentered-voltage standard deviation (AC RMS label), 99th percentile
absolute voltage step, and Welch band powers 1–40, 8–13, 49–51 and 59–61 Hz.
Welch uses at most 512 samples per segment and assumes the observed 128 Hz rate.

Limit: the historical segmentation implementation does not explicitly split on
every stable_segment/status marker. Use recordings whose continuity fields are
complete and inspect gaps; this is a research utility, not a production quality
engine. All analysis validity flags remain false for physiology/contact claims.
