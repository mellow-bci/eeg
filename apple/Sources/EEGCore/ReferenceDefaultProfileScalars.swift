/// Actual scalar assignments in installed loadDefaultProfile. Comparison-only:
/// this is neither a trained profile nor a replacement for explicit runtime
/// sensitivity, prior, neutral scaling or background configuration.
enum ReferenceDefaultProfileScalars {
    enum Value: Equatable, Sendable {
        case integer(Int32)
        case floating(Double)
    }
    static let values: [String: Value] = [
        "cognitiv-winSizeInSec": .floating(1.0),
        "cognitiv-stepSizeInSec": .floating(0.125),
        "cognitiv-isBandPower": .integer(1),
        "cognitiv-maxActiveActions": .integer(4),
        "cognitiv-activationThreshold": .integer(4),
        "cognitiv-action1Threshold": .integer(5),
        "cognitiv-action2Threshold": .integer(5),
        "cognitiv-action3Threshold": .integer(5),
        "cognitiv-action4Threshold": .integer(5),
        "cognitiv-actionStability": .floating(0.5),
        "cognitiv-honeyLevel": .floating(0.01),
        "cognitiv-maxNumOfNoisyChannels": .integer(4),
        "cognitiv-enableErrorSetClassifiers": .integer(0),
        "cognitiv-maxErrorSetClassifiers": .integer(20),
        "cognitiv-enableCachedClassifiers": .integer(1),
        "cognitiv-maxCachedClassifiers": .integer(20),
        "cognitiv-rebuildSignature": .integer(0),
        "cognitiv-minEpochsToTrain": .integer(12),
        "cognitiv-maxEpochsToTrain": .integer(100),
        "cognitiv-maxGaussianPerClass": .integer(10),
        "cognitiv-trainingAction": .integer(1),
        "cognitiv-trainingControl": .integer(0),
        "cognitiv-startAfterTimeInSec": .floating(1.0),
        "cognitiv-trainingTimeInSec": .floating(8.0),
        "cognitiv-autoSamplingNeutral": .integer(0),
        "cognitiv-trainingAcceptThreshold": .floating(0.0),
        "cognitiv-lastTrainingScore": .floating(0.0),
        "cognitiv-overallSkillRating": .floating(0.0),
        "cognitiv-crossValidate": .integer(0),
        "cognitiv-totalOfTimesTraining": .integer(0),
    ]

    /// Static program action vocabulary, not trained or hardware-qualified commands.
    static let actionIDs: [UInt32] = [1,2,4,8,16,32,64,128,256,512,1024,2048,4096,8192]
    static let zeroMatrices: [String: ReferenceProfileCodec.Matrix] = [
        "cognitiv-brainMapCoords": .init(rows: 14,columns: 2,elements: Array(repeating: 0,count: 28)),
        "cognitiv-actionSkillHistory": .init(rows: 3,columns: 14,elements: Array(repeating: 0,count: 42)),
        "cognitiv-actionSkillHistoryCount": .init(rows: 1,columns: 14,elements: Array(repeating: 0,count: 14)),
        "cognitiv-numberOfTimesActionTraining": .init(rows: 1,columns: 14,elements: Array(repeating: 0,count: 14)),
    ]
    // Default Matrix constructor values; do not imply active/trained commands.
    static let emptyMatrixKeys = ["cognitiv-activeActions","cognitiv-trainedActions"]

    /// Opt-in default training config; timing rate/step remain caller-provenance.
    /// Profile overrides can instead be supplied directly to the lifecycle.
    static func trainingConfiguration(samplingRate: UInt64, stepSamples: UInt64)
        -> ReferenceTrainingLifecycle.Configuration {
        .init(samplingRate: samplingRate,stepSamples: stepSamples,
              startAfterSeconds: 1,trainingSeconds: 8,minimumEpochs: 12,maximumEpochs: 100)
    }
}
