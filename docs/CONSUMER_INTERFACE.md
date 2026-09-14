# EEG consumer interface and ownership

Product direction: standalone and local-first. Cast is an optional future consumer,
not the application host or a requirement for capture, replay, analysis or training.
Core operation must not depend on internet access, accounts or subscription services.

Status: proposed integration boundary, grounded in current source; not a released
network API. This document does not assert that Cast schemas or permissions have
been mapped. No Cast source was changed for this checkpoint.

## Existing contracts to preserve

| Source | Actual contract | Consumer constraint |
|---|---|---|
| `processing/contract.py` | `eeg.canonical.v2`: immutable 14-channel ADC and optional µV samples; counter, sample index, arrival timestamp, source, configuration, epoch, stable segment and explicit continuity/stability | Preserve unknown fields as unavailable. Do not infer stable transport from missing metadata. |
| `apple/Sources/EEGCore/RecordingStore.swift` | Append-only `eeg-native-v1` JSONL with stream start, sample/event records and final sample-count summary | Import through the existing adapter; do not create a second decoder. A missing summary is not a finalized recording. |
| `processing/features.py` | `eeg.features.v1` design plus exact configuration hash, 70 log-band powers and artifact observations | Numerical feature usability is not command readiness or psychological meaning. |
| `processing/mental.py` | `eeg.mental-profile.v2`; `eeg.command-proposal.v1` with explicit rejection and unvalidated experimental candidates | Consumers must retain `command=null` and `system_control_enabled=false`; a candidate is evaluation evidence, not an action. |
| `processing/workflow.py` | Shared extraction, training and session-separated evaluation | User interfaces invoke this semantic workflow; they must not reimplement scoring in UI code. Native implementation must match the reference before replacing it. |

## Ownership

The local EEG service owns the headset connection, packet accounting, source timing,
raw file and recording lifecycle. It must continue recording independently of a UI
or workspace connection. This is a target requirement: the current native app still
owns acquisition in `AcquisitionModel`; separation into an independently supervised
service has not been implemented or qualified.

A workspace may own participant references, experiment plans, review annotations,
sharing policy and links to results. Scientific results are immutable derived
artifacts referencing source identity/content digest, exact sample range, processor
and configuration version. Corrections create a new artifact; they do not overwrite
raw measurements or silently change prior conclusions.

Native recording filenames are currently UUID-based. A future external recording
ID must be mapped explicitly; a path is neither authorization nor a portable ID.
Raw files remain local unless an explicit configured transfer is performed.

## Proposed operation families

1. Inspect device/status and compatible configuration, with explicit unsupported states.
2. Start/stop recording through one acquisition owner; use request IDs for retry safety.
3. List recordings and retrieve paginated original samples by opaque recording ID.
4. Subscribe to bounded display updates. A slow subscriber may lose display updates,
   but its dropped ranges must be reported and must not cause archival sample loss.
5. Attach versioned markers/labels with author, timing basis and verification status.
6. Request analysis by recording digest and sample range; return result provenance,
   rejected windows, gaps and unknowns alongside numerical results.
7. Train/evaluate/preview profiles using the same verified window and label rules.
8. Export an authorized recording/result with explicit units and format.

These are operation families to implement, not callable endpoints today. Avoid
publishing route names or a client SDK before lifecycle/error semantics are tested.

## Cowork and other analysis consumers

Give consumers a result artifact and permitted source ranges, not unrestricted local
filesystem access. Tools should return measured values, method/configuration,
limitations and evidence links. An assistant can propose an analysis or interpretation;
its text cannot change label verification, hardware qualification or output arming.
Unknown psychological meaning remains unknown even if a vendor score correlates.

## Acceptance before integrating a workspace

- Recording survives UI closure, renderer overload and workspace disconnection.
- Exactly one process owns device acquisition; retries cannot duplicate starts/events.
- Subscriber queues are bounded and overflow has explicit range/gap reporting.
- Requests resolve opaque IDs under authorization; paths from callers are not trusted.
- Revocation prevents further sample access; local-only operation produces no remote egress.
- Replay and live analysis yield the same results for the same canonical windows.
- Profile, label and source versions are pinned for reproducible evaluation.
- Table, Kanban and Calendar are views of the same objects; waveform review opens the
  same recording identity rather than copying it into a parallel application store.
- No consumer can convert an unvalidated candidate into a reliable mental command.

Cast object mapping, authentication transport, independent service supervision,
scientific rendering benchmarks and accessibility qualification remain open work.
