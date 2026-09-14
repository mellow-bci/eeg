# Research history and rejected assumptions

This history summarizes the complete original chronological STATUS.md retained
under `archive/current-state/`. The preserved file contains intermediate claims
that were corrected later; the current status is in CURRENT_STATE.md.

1. **Hardware access:** distinguished charging/configuration USB observations
   from Bluetooth data access; used the actual EPOC X and read metadata.
2. **Initial decode exploration:** older EPOC framing/key assumptions were tested
   and did not establish the observed 0740 path. `check_legacy_framing.py` remains
   an experiment; no legacy fallback is enabled in the current decoder.
3. **Static protocol trace:** inspected the user's installed CortexService binary
   without attaching a running process. Traced V4 seed derivation, XOR/AES decode,
   record parsing, channel output mapping and configuration-dependent scaling.
4. **Live and replay path:** built one pipeline retaining original bytes, raw ADC,
   counters, epochs and explicit failures. Live decoding then worked on hardware.
5. **Worn experiments:** used audible open/close cues so the participant could
   reopen their eyes without watching a screen; later ran blink cues. Alpha result
   was inconclusive; frontal blink-associated response was observed without an
   independently verified blink detector.
6. **Raw CQ:** traced slots and channel names but withheld quality classes.
7. **Official reference attempt:** EmotivPRO could show the physical headset and
   record TEST24; an earlier UI also showed a simulated device. A simulated-device
   screen was not accepted as proof of hardware EEG. PRO-LITE export was blocked.
8. **Local recording recovery:** reconstructed file-key retrieval from static
   code; authenticated read recovered TEST24. A tampered-copy test failed as expected.
9. **Same-input validation:** resolved the already-connected CoreBluetooth peripheral
   and collected notifications alongside Cortex on M4. Full-channel matches established
   map/scale/raw CQ equivalence on stable samples; startup anomalies remained.
10. **Hardening:** added gated consumer delivery, stable segments, failure propagation,
    arrival/stale-input handling, private output, budget, lease and shutdown tests.
11. **Repeated validation:** three reconnect cycles, three-minute soak and fresh
    two-minute Cortex retest. Longer standalone production qualification remains.
12. **Private repository snapshot:** code, all original relevant artifacts and
    current documentation were consolidated in autonomy-cloud/eeg with Git LFS.

No milestone means “thought decoding works.” No account credential or cloud
transcription model is needed for the raw BLE decoder. Recovering a proprietary
recording format does not make the entire vendor system our original invention;
our contribution here is the independent acquisition/recovery implementation,
validation procedure, tests and retained engineering evidence.
