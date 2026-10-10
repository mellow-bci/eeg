# Upstream delivery and profile edit trace

Read-only M4 static LLDB arm64 CortexService, binary SHA256 cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a. No process attach or vendor learned asset extraction. Captures contain complete named bodies; exception tails are not ordinary successful paths.

## Two cadence layers

DetectionsForDevice::processNewData 0x100ae9e8c calls six SynchronisedSubscription::processNewData objects. Mental subscription is +0x668: initSubscriptions0x100ae93cc selects the mental detector +0x9f0, gets its window/step and calls subscription.init at0x100ae93fc with primary stream numeric10. CognitivDetection constructor sets outer window and step both0.125 (see ../manager-cadence-continuation-20261011/outer-window.txt). This outer nonoverlapping duration is distinct from the manager profile's 1s/0.125s default feature window.

Subscription.init0x10122ba5c checks buffer, nonempty stream list, window>=step and step>0; primary stream permits numeric0 or10. It computes signed truncated sampleRate*window into +0x3c and sampleRate*step into +0x40 at0x10122bb18..3c, then cursor=startIndex at0x10122bb48..50. Our bounded adapter supports positive products >=1 and Int32 range, rather than emulating unsafe zero/overflow cases.

processNewData0x10122bbc0 loops readData(windowSamples,false), emits newData only for a nonempty returned map, and repeats until an empty map. No periodic wall-clock timer is established by this body. Device-status timestamp accompanies emission at0x10122bc18..28; it is not inferred from an EEG sample's timestamp.

readData0x10122c0d8 clamps cursor to the retained buffer start when it fell behind, logging dropped samples at0x10122c328..334. At0x10122c340..358 it waits until cursor+requested count<=endIndex. It takes timestamps at cursor and cursor+count-1; searchData gets the time interval. Its permissive-search flag is forced by caller or, on ordinary reads, by cursor<startIndex+100 AND isAlmostFull(100),0x10122c390..3d0. Failed search returns empty without advancing by step. Successful cross-stream map construction advances cursor by configured step at0x10122c85c..868.

ReferenceSubscriptionCadence implements these index/read/drain rules with an explicit supplied search result and own maximumReads bound. It DOES NOT implement timestamp search, cross-stream clipping, SamplesBuffer retention, interpolation, dispatch threads or transport. Capacity failure is observable and retains already-performed reads. Tests cover drop/search-failure boundaries, margin100 equality, truncation and outer16-sample blocks feeding the shared inner manager at128Hz (32 blocks ->25 overlapping128-sample epochs).

## Detector input contract

Detection::run0x101234458 asserts delivered column count equals signed truncated outer window*configured rate at0x101234490..4bc. It checks input row and selected-ID/index-list shapes, copies supplied CQ/flags, selects channel rows at0x101234590 and dispatches virtual detect at0x1012345b0. Our raw comparison wrapper receives already selected rows, now sharing ReferenceManagerCadence filter/stream execution; it does not claim upstream interpolation parity. Random EEG interpolation is enabled in the mental constructor but implementation/inputs remain a separate evidence gate.

## Profile edit versus replacement

updateProfileValues0x100ae9980 first validates requested fields via mental and facial parameterSanityCheck calls0x100ae9b1c/30. Accepted map application calls EmoProfile.set for each field0x100ae9c88, then emits profileValuesApplied0x100ae9cc4. Its complete body contains no detector stop/init or subscription reinit call. This proves this path does not itself rebuild timing/bands, not that every signal consumer elsewhere is absent.

setTrainingProfile0x100ae9894 replaces the profile, and if mental enabled+0x4e0, calls mental.stop at0x100ae9930 followed by mental.init at0x100ae9938. This is an actual recipe reload path. The subscription outer timing remains the constructor0.125; loaded inner recipe is re-resolved by init. Exact asynchronous signal consumers and deployed execution observations remain unverified.

No new vendor assets needed. Matching same-profile invocation traces, timestamp-search/reference output and physical CQ transitions are still necessary for full runtime equivalence.

Single-field checks were closed with companion bodies in ../runtime-recipe-continuation-20261011/: for valid QVariant/non-null profile, Cognitiv accepts keys other than activeActions/trainingControl with return0; facial checker similarly only specializes its own training keys. Thus recipe edits pass both checks without direct reinitialization in this setter. Signal-consumer behavior elsewhere remains outside this bounded result.
