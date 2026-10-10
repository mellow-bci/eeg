# Raw selected-channel comparison workflow

This is independent composition of existing body-derived kernels, not observed Cortex equivalence or a production acquisition change. No vendor assets were accessed or added.

## Evidence boundaries

The deployed-feature continuation traces manager input filter before MatrixStream, then median preprocessing, Hamming, FFT, bands, power/ratio features and processed-feature routing to detection. The preprocessing continuation supplies the input-filter recurrence. Runtime profile and command kernels retain their own traced equations. See `../deployed-feature-continuation-20261011/TRACE.md` and `../preprocessing-continuation-20261011/TRACE.md` plus source comments in the reused kernels.

`ReferenceRawMentalWorkflow` accepts already decoded, explicitly selected channel rows. It does not determine actual device channel selection, deployed bands/coordinates/window/step, background toggle, class priors or learned profile, sensitivity or overall contact-quality decoding. These remain explicit caller inputs. There is no application/OS event dispatch.

## Scheduling

Each invocation emits at most one available epoch, including an invocation with an empty outer input array. It never drains the stream automatically. The caller must reproduce manager tick timing and quality at the emitted epoch. Transport partition invariance tests explicitly drain available epochs with empty ticks so the epoch schedule is equal. These tests do not assert equivalence between different real manager schedules.

## Independent failure policy

Invocations are transactional: malformed blocks or downstream numeric failures restore every prior state. `resetForGap()` explicitly clears the filter, epoch buffer, processed-feature background and scoring histories and increments a segment counter. The caller must invoke it on a discontinuity; no vendor gap detector is inferred. Invalid quality preserves feature diagnostics and background exclusion but emits no candidate and resets scoring history. This fail-closed reset is our policy, not a claim about the vendor reset path. An invalid numerical window raises an error rather than publishing a fabricated feature or command.

## Authored tests

`ReferenceRawMentalWorkflowTests` compares complete emitted stages across 48-, 1-, 3-, 8- and 17-sample partitions; uses independently authored class statistics fitted through the existing PCA/canonical/Gaussian builder and deployed-runtime bridge; checks invalid quality/background initialization; checks explicit gap reset against a fresh pipeline; and verifies malformed/numerically invalid invocation rollback against a fresh pipeline. Signals and class statistics are mathematical fixtures, not physiological or Cortex recordings.

Tests were authored without running a build in this subtask; the coordinating agent owns the combined build. A passing replay proves internal deterministic composition only. Matched Cortex stage outputs, actual deployed recipe and hardware/physiological qualification remain separate gates.
