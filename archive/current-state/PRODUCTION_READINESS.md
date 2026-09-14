# EPOC X acquisition release gates

Scope: direct BLE EEG acquisition on macOS for the observed EPOC X device,
revision 0740, configuration 018000102010. Production status: NOT RELEASED.
This does not establish clinical validity or a brain-intent decoder.

- [x] Same-sample electrode ADC and voltage agreement against unmodified Cortex.
- [x] Same-sample raw contact-quality agreement.
- [x] Raw packets and rejected samples retained; consumer gated until stable.
- [x] Three deliberate reconnect cycles recover to stable without manual intervention.
- [ ] Longer live run with no post-stability loss/error and bounded memory.
- [x] Acquisition callback, consumer and storage failures terminate safely.
- [x] Arrival gaps invalidate stability even if wrapping counters look continuous.
- [x] Missing/unsupported configuration never reaches a calibrated-data consumer.
- [ ] Reproducible install, device selection, permissions and graceful shutdown.
- [ ] Contact-quality class calibration across good and poor contacts validated.
- [ ] Independent-reader-only lifecycle tested with Cortex absent.
- [ ] Supported-platform soak duration and release acceptance recorded explicitly.

No runtime release flag is inferred from passing unit tests or one short run.
Vendor file recovery is a validation tool, not a production acquisition dependency.

Evidence: three-minute run passed without post-stability issues; this is an initial
soak, not sufficient duration for production release. 25 tests pass.
