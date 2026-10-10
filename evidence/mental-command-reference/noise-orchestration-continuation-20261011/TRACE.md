# Error-set detection orchestration and processed feature routing

Pinned arm64 CortexService SHA256: cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a.
Static LLDB only: buildClassifier/run, both runDetection overloads, background filtering and unnamed clone helper. No target execution, profile extraction or vendor asset copied.

## Body evidence

- Noisy overload 100b32444 starts validity=true. Empty classifier or feature input clears output and replaces validity with manager+79.
- 100b32640..32664 compares feature channel metadata doubles against UInt64 channel IDs converted to doubles. No intersection uses the base classifier. Ordered IDs are not deduplicated.
- 100b326a8 cache lookup precedes the maximum check. A hit classifies immediately and increments shared classifier+460 at 100b32718..32724.
- On miss, 100b32854 compares signed configured maximum against vector length. Excess clears output and sets validity=false. The bounded Swift contract requires an Int32 configured maximum and addressable Swift arrays; enormous vendor integer truncation cases are unsupported.
- 100b328f0 clone helper 100b3638c allocates a shared classifier and invokes copy-construction helper 100b1ba40. 100b32970 calls buildClassifier(profile,false,clone); success inserts the bank entry, classifies, and increments reuse. Failed fitting clears output and invalidates it. No successful fit is fabricated by our callback boundary.
- No channel masking occurs in the captured noisy overload. buildClassifier loads classes/features/Gaussians from the profile DB and invokes GaussianTraining::run. This does not establish a recovered noisy-channel-specific refitting recipe; the rebuild callback remains explicit.

## Corrected caller interpretation

The prior deployed-feature TRACE stated that detection consumed original features. This was incorrect. run converts features into sp+e0 at 100b2dd98; clean features are copied or background-filtered into sp+90 at 100b2ddd4..2de48. Auto-neutral, training, and both detection calls receive sp+90 at 100b2de50/2de6c/2de94/2deb8. Original measurements remain separately preserved in our contract.

The noisy ID vector at sp+38 is zero-initialized at 100b2dbd0..2dbd4 and passed at 100b2de9c. Its only other occurrences in this run body are cleanup. Thus this traced caller passes an empty list; no automatic noisy-channel extraction is established here. We do not generalize this observation to all possible binary call sites.

## Implementation and validation boundary

ReferenceNoiseHandling models routing, callback failure, shared cache identity and validity, with six deterministic tests including processed-feature routing. ReferenceProcessedEpoch preserves original features, skips invalid input without updating background, and provides one processed vector for all consumers. Internal comparison only; not enabled in the independent live trainer. Matched trained-profile outputs and prospective physiological evaluation remain absent. No vendor learned assets required for this checkpoint.

Final verification: focused171 tests (169pass,2skip,0fail), broad361 tests
(357pass,4skip,0fail). The broad build preceded the last runtime PSD-intermediate
change; final focused coverage includes all affected reference kernels.
