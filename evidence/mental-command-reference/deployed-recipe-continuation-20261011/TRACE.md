# Deployed default recipe, coordinate order and channel dispatch

Installed CortexService arm64 SHA256 `cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a`; bounded static LLDB bodies and readonly constants. No vendor learned assets, profiles, binaries, credentials or execution bundled. This is a comparison preset, not current-device verification.

## Actual default construction

`CognitivDetection::init` (`0x100b26cac`) reads profile key `cognitiv-version`. Invalid QVariant or version string unequal to global version `0x1033a4430` causes `loadDefaultProfile` at `0x100b26da4..da8`; matching version retains its runtime profile values. Static version initializer `0x100b2c98c..9b4` builds string `20180327`.

`loadDefaultProfile` (`0x100b26e54`) allocates a 14-double list, copies constants at `0x102647cc8` (`26edc..6f00`), constructs a 1x14 Matrix (`26f0c..f1c`) and stores it as `cognitiv-bands` (`27114..150`). Constants read directly:

`4,7,8,12,13,17,18,22,23,26,27,30,31,57`

Paired band edges: `(4,7),(8,12),(13,17),(18,22),(23,26),(27,30),(31,57)`. The routine constructs `cognitiv-winSizeInSec=1.0` at `26fec..ff0`, `cognitiv-stepSizeInSec=0.125` at `27080..84`, and `cognitiv-isBandPower=1` at `271b0..b4`. At `28aa4..ab4` all temporary-map fields are applied to the EmoProfile through `set`, not merely prepared unused constants.

Manager init retains the runtime profile path documented in `../neutral-training-continuation-20261010/init-buffer-reset.txt`: `getMatrix` bands at `0x100b38104`, requires even column count at `38134..13c`, copies exactly the first `cols` linear elements, obtains isBandPower via toInt and tests equality to1 (`38310..318`), and obtains both durations through QVariant.toDouble (`3839c..3ac`, `38414..424`). It creates the stream using supplied sampling rate at `38468..47c` and resets it. Unsupported malformed matrix/non-numeric QVariant coercions are not emulated by this new preset.

`EmoProfile::get` is map lookup (`0x10123558c`), with missing key producing default QVariant; `getMatrix` (`0x10123569c`) tests convertibility and calls converter `0x100b1b164`, otherwise reaches failure helper `0x10246ce7c`. No hidden numeric fallback can be inferred from these getters. Default initialization is conditioned by version as above.

## Exact generated feature coordinates

`generateChannelBandMapping` (`0x100b20c3c`) returns empty matrix if C<=0 or B<=0 (`20c6c..7c`). Power branch allocates C*B rows,2 columns; loops channel outer (`20d5c..68`), band inner (`20d20..58`), writing `(channel,band)`.

Ratio branch (`20e14..fc0`) allocates four columns. Denominator channel `c` is w23/d8; denominator band `b` w25/d10. Numerator channel `a` is w27/d11 from0 throughc, numerator band `d` w28/d12 from0 throughb. It skips the exact same pair at `20fb0..bc`. Writes `(a,d,c,b)` at `20f4c..98`, preserving loop order c,b,a,d. Count is `C(C+1)/2 * B(B+1)/2 - C*B`, verified directly from these loops. This is not a flattened-feature all-pairs upper triangle: C=2,B=2 emits five rather than six ratio rows, omitting (0,1)/(1,0).

Independent adapter reuses existing `ReferenceDeployedFeatures.Feature` and extraction arithmetic. New caps C,B<=70, explicit caller maximumFeatures and Int32 row-count bound are our resource support policy, not vendor defaults. Negative/zero sizes return empty as the traced branch; overflow dimensions unsupported. Default14-channel/seven-band power recipe has98 raw feature coordinates: the separate retained PCA/Gaussian density bound70 does not cap raw feature count at70.

## Target channels and actual input positions

`CognitivDetection::configure` (`0x100b26bdc`) reads HeadsetType numeric IDs1...10 through readonly pointer table `0x1031383c0`; out of range uses global `0x1033a43d0`. Static table entries:

- IDs1,2 -> list `0x1033a4418`.
- IDs3...8 -> list `0x1033a43d0`.
- IDs9,10 -> list `0x1033a43e8`.

Initializer `0x100b2a35c` tail constructs those lists:

- `0x100b2c770..7f0`: 14 IDs at43d0, first12 readonly `0x102647c7c` = `40,43,45,51,54,64,69,77,82,92,95,101`; last103,106 packed at7c8..d0.
- `0x100b2c808..870`: 2 IDs at43e8, packed54,92.
- `0x100b2c900..974`: 5 IDs at4418, first4 readonly `0x102647cb4` =40,54,72,92; last106 at958..95c.

The adapter exposes numeric dispatch, with no inference of which enum names correspond to these IDs and no qualification of other hardware. Default TrainingProfile.eegChannels metadata is a separate concept; this detector chooses its target list before base configure.

Base `Detection::configure` (`0x1012341b0`) stores caller input channel IDs at+10, iterates target IDs at+28 in their order, scans input IDs from first position (`23428c..2c4`), writes the found position (`234274..27c`), and returns false with warning if a target is missing (`23430c` onward). `inputIndices` implements first matching position/order; failure is an explicit independent error rather than logger+false. Actual raw data row ordering still must be supplied by verified capture provenance.

## Cadence and remaining gates

`CognitivDetection::init` gets `Detection::samplingRate` and supplies it to manager (`26dac..dc4`). This is runtime configuration, not an inferred128Hz default. Existing stream evidence proves truncating duration*rate, single nextWithRemoval per manager invocation, cursor/removal/reset behavior. Default0.125s step means16 samples at explicit128Hz, but does not prove scheduler calls at8Hz; detect (`26c58..c98`) forwards once to manager, whose upstream scheduling remains untraced. Whole-second time(NULL) manager timestamps are not sample timestamps.

Remaining current-device comparison inputs: actual HeadsetType enum provenance, input row IDs/sample rate, loaded-profile overrides and scheduler lifecycle, matched trained signature/priors/sensitivity/reference outputs. Learned parameter assets are not needed for the recovered static recipe, and none are required/copied by this adapter. Our fitted own-value round trips and static-derived tests remain distinct from trained Cortex/runtime parity and physiological command validation.

## Independent validation

Three tests: actual default constants/explicit128Hz stream counts/overrideability; hand-derived asymmetric2x2 power/ratio order with analytic dB outputs and caller-cap failure; actual numeric target dispatch/first input position/missing-channel failure. Root coordinates execution; no builds launched by this agent. No UI, acquisition or existing trainer edits.

## Complete scalar default construction continuation

`default-scalars.tsv` indexes every directly constructed numeric QVariant default: exact key, integer/double type, value, QVariant constructor, string-key literal, map-entry helper and actual `stp q0,q1,[x0]` value-store addresses. The full body is `default-configure-detect.txt`; all map fields are applied via EmoProfile.set at `0x100b28aa4..ab4`. These are actual profile construction assignments, not inferred getter fallbacks. They apply only when the init version check selects default construction; a matching loaded profile may override them.

| Actual key(s) | Actual constructed default |
| --- | --- |
| cognitiv-winSizeInSec / cognitiv-stepSizeInSec | double 1.0 / 0.125 |
| cognitiv-isBandPower | integer 1 |
| cognitiv-maxActiveActions | integer 4 |
| cognitiv-activationThreshold | integer 4 |
| cognitiv-action1Threshold through cognitiv-action4Threshold | integer 5 each |
| cognitiv-actionStability | double 0.5 |
| cognitiv-honeyLevel | double 0.01, exact bits 0x3f847ae147ae147b |
| cognitiv-maxNumOfNoisyChannels | integer 4 (count, not enable/disable toggle) |
| cognitiv-enableErrorSetClassifiers / cognitiv-maxErrorSetClassifiers | integer 0 / 20 |
| cognitiv-enableCachedClassifiers / cognitiv-maxCachedClassifiers | integer 1 / 20 |
| cognitiv-rebuildSignature | integer 0 |
| cognitiv-minEpochsToTrain / cognitiv-maxEpochsToTrain | integer 12 / 100 |
| cognitiv-maxGaussianPerClass | integer 10 |
| cognitiv-trainingAction / cognitiv-trainingControl | integer 1 / 0 |
| cognitiv-startAfterTimeInSec / cognitiv-trainingTimeInSec | double 1.0 / 8.0 |
| cognitiv-autoSamplingNeutral | integer 0 |
| cognitiv-trainingAcceptThreshold / cognitiv-lastTrainingScore / cognitiv-overallSkillRating | double 0 each |
| cognitiv-crossValidate / cognitiv-totalOfTimesTraining | integer 0 each |

`ReferenceDefaultProfileScalars.values` retains these constructor types. It does not reinterpret thresholds as probabilities, psychological scores, sensitivity percentages or neutral density scaling. The opt-in `trainingConfiguration` composes existing real ReferenceTrainingLifecycle with startAfter1, training8, minimum12, maximum100 and explicit caller sampling rate/step; it does not replace lifecycle acceptance rules or falsely mark training successful. Existing workflow initialization remains unchanged.

## Nonnumeric defaults and action initializer closure

Default profile also has version `20180327`, bands described above, and empty active/trained action matrices (`0x100b27248`, `0x100b280b4` default Matrix constructors). Static action-list initializer `0x100b2a5a0..620` allocates14 ints at BSS list `0x1033a3a18`, with data pointer at3a20 and size at3a28. Readonly constants `0x102647c44..c70` hold1,2,4,8,16,32,64,128,256,512,1024,2048; tail at `0x100b2a5f8..600` packs4096 and8192. Size14 is stored at `0x100b2a61c..620`. Captures: action-count-add-xrefs, action-count-initializer, action-count-constants. Initial xref search only found the direct count load; ADD-based list-construction search resolved the store. These fourteen IDs are static command vocabulary, not fourteen trained commands or qualified hardware controls.

`loadDefaultProfile` count load `0x100b26f20..24` obtains14. Thus constructors create zero-filled actionSkillHistory3x14 (`26f28..38`), actionSkillHistoryCount1x14 (`26f3c..4c`), brainMapCoords14x2 (`27b5c..6c`), and numberOfTimesActionTraining1x14 (`28490..4a0`); each later QVariant/map assignment uses its named key. The comparison adapter reuses ReferenceProfileCodec.Matrix for these shapes, and separately lists empty active/trained keys. It does not convert zero state into a fitted classifier.

ActionRating construction iterates14 IDs (`0x100b286bc..6c4`, `28734..44`), builds key prefix `cognitiv-actionRating` (`287a4..b0`), appends the actual integer ID via stream insertion (`287c0..c8`), constructs double0 (`287cc..d4`) and inserts/stores it (`28818..8a0`). This is zero initial score per enum ID. No learned score assets are implied; formatting/coercion outside this static known loop is not emulated by the numeric adapter.

## Explicit remaining defaults boundary

No sensitivity, prior, neutralScale, background-enable or noise-enable field assignment occurs in this complete loadDefaultProfile body. Their defaults cannot be invented from similarly named getters, activation thresholds, honeyLevel or maxNoisyChannels. Existing independently traced sensitivity and neutral training paths retain their explicit inputs; loaded-profile/config provenance and actual matching Cortex reference output remain required for those runtime comparisons. Cached-classifier enable/count assignments are configuration facts, not proof of warm cache contents or cache replacement policy. Full algorithm/runtime parity and physiological mental-command validation are not established by default construction.

Three additional tests exercise real training-lifecycle composition including insufficient-epoch rejection, exact typed threshold/cache/noise/neutral values, and independent zero-state matrix shapes/action vocabularies. Parent coordinates builds. No vendor learned assets are needed for these static defaults.
