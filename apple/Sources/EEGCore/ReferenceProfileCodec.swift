import Foundation
import CoreFoundation

/// Bounded inverse Matrix conversion, not a complete profile/storage codec.
/// Evidence: inverse-profile-continuation-20261011; no vendor profile values.
enum ReferenceProfileCodec {
    indirect enum Value: Equatable {
        case number(Double), string(String), bool(Bool), null
        case array([Value]), object([String: Value])
    }
    struct Matrix: Equatable {
        let rows: Int
        let columns: Int
        /// Row-major: operator(row,column) addresses columns*row+column.
        let elements: [Double]
        static let empty = Matrix(rows: 0, columns: 0, elements: [])
        func rowValues() throws -> [[Double]] {
            if self == .empty { return [] }
            let (count, overflow) = rows.multipliedReportingOverflow(by: columns)
            guard rows > 0, columns > 0, !overflow, count == elements.count else {
                throw InputError.unsupportedShape
            }
            return (0..<rows).map { row in Array(elements[(row * columns)..<((row + 1) * columns)]) }
        }
        static func fromRows(_ values: [[Double]]) throws -> Matrix {
            guard let first = values.first else { return .empty }
            guard !first.isEmpty, values.allSatisfy({ $0.count == first.count }),
                  values.joined().allSatisfy(\.isFinite) else { throw InputError.unsupportedShape }
            return Matrix(rows: values.count, columns: first.count, elements: values.flatMap { $0 })
        }
    }
    struct MatrixResult: Equatable {
        let matrix: Matrix
        /// Vendor schema flag only; does not validate classifier usefulness.
        let schemaAccepted: Bool
    }
    enum InputError: Error, Equatable {
        case unsupportedDimensions, unsupportedShape, nonfiniteElement, resourceLimit
        case unsupportedUnsignedVector
        case unsupportedInteger, unsupportedCountRoundTrip
        case invalidJSON, nestingLimit
    }
    struct WeightMeanVariances: Equatable {
        let weight: Matrix
        let mean: Matrix
        let variances: [Matrix]
    }
    struct Classifier: Equatable {
        let weightMeanVariances: [WeightMeanVariances]
        let classRefIDs: [Int32]
        let uniqueFeatureIndices: [UInt64]
        let coeff: Matrix
        let pcMeans: Matrix
        let eigenvec: Matrix
        let meanTot: Matrix
        let channelInUse: Matrix
        let numOfValidFeatures: UInt64
        let useCount: UInt64
    }
    struct ClassifierResult: Equatable {
        /// Nil for outer schema rejection: no invented default Classifier fields.
        let classifier: Classifier?
        let schemaAccepted: Bool
    }
    struct GaussianDataResult: Equatable {
        let distribution: ReferenceGaussianPooling.Distribution?
        let schemaAccepted: Bool
    }
    struct GaussianAlgebraResult: Equatable {
        let entry: ReferenceTrainingBank.ClassEntry?
        /// The vendor outer flag is not cleared when individual data objects fail.
        let schemaAccepted: Bool
        /// Our observability addition: Cortex logs and omits these entries.
        let rejectedDistributionIndices: [Int]
    }
    enum ProfileValue: Equatable {
        case number(Double), string(String), matrix(Matrix)
        case gaussianAlgebra(ReferenceTrainingBank.ClassEntry), classifier(Classifier)
    }
    struct ProfileResult: Equatable {
        let properties: [String: ProfileValue]
        let omittedKeys: [String]
        let rejectedGaussianIndices: [String: [Int]]
    }
    /// Shape dispatch order matches jsonObjectToProfile. Sorted traversal is our
    /// deterministic policy; it is not a claim of identical Qt Unicode ordering.
    static func decodeProfile(_ object: [String: Value], maximumElements: Int) throws -> ProfileResult {
        var properties: [String: ProfileValue] = [:], omitted: [String] = []
        var rejected: [String: [Int]] = [:]
        for key in object.keys.sorted() {
            switch object[key]! {
            case .number(let number):
                guard number.isFinite else { throw InputError.nonfiniteElement }; properties[key] = .number(number)
            case .string(let string): properties[key] = .string(string)
            case .object(let nested):
                let matrix = try decodeMatrix(nested,maximumElements: maximumElements)
                if matrix.schemaAccepted { properties[key] = .matrix(matrix.matrix); continue }
                let gaussian = try decodeGaussianAlgebra(nested,maximumElements: maximumElements)
                if gaussian.schemaAccepted, let entry = gaussian.entry {
                    properties[key] = .gaussianAlgebra(entry)
                    if !gaussian.rejectedDistributionIndices.isEmpty { rejected[key] = gaussian.rejectedDistributionIndices }
                    continue
                }
                let classifier = try decodeClassifier(nested,maximumElements: maximumElements)
                if classifier.schemaAccepted, let value = classifier.classifier { properties[key] = .classifier(value) }
                else { omitted.append(key) }
            default: omitted.append(key)
            }
        }
        return .init(properties: properties,omittedKeys: omitted,rejectedGaussianIndices: rejected)
    }

    private static func matrixValue(_ matrix: Matrix) -> Value {
        .object(["rows":.number(Double(matrix.rows)),"cols":.number(Double(matrix.columns)),
                 "elements":.array(matrix.elements.map(Value.number))])
    }
    static func decodeGaussianData(_ object: [String: Value], maximumElements: Int) throws -> GaussianDataResult {
        guard Set(object.keys) == Set(["updateTime","numberOfEpochs","covariance","average"]),
              case .number = object["updateTime"],
              case .object(let countsObject) = object["numberOfEpochs"],
              case .object(let covarianceObject) = object["covariance"],
              case .object(let meanObject) = object["average"] else {
            return .init(distribution: nil, schemaAccepted: false)
        }
        let time = UInt32(bitPattern: try integer(object["updateTime"]!))
        let counts = try decodeMatrix(countsObject,maximumElements: maximumElements)
        let covariance = try decodeMatrix(covarianceObject,maximumElements: maximumElements)
        let mean = try decodeMatrix(meanObject,maximumElements: maximumElements)
        guard counts.schemaAccepted, covariance.schemaAccepted, mean.schemaAccepted else {
            // The body sets no GaussianData fields unless all three imports succeed.
            return .init(distribution: nil, schemaAccepted: false)
        }
        if counts.matrix == .empty && covariance.matrix == .empty && mean.matrix == .empty {
            return .init(distribution: .init(counts: [],mean: [],covariance: [],updateTime: time),schemaAccepted: true)
        }
        // Existing Distribution represents row-vector statistics only. This is a
        // deliberate supported-domain gate, not an inferred vendor shape assertion.
        let n = counts.matrix.columns
        guard n > 0, counts.matrix.rows == 1, mean.matrix.rows == 1, mean.matrix.columns == n,
              covariance.matrix.rows == n, covariance.matrix.columns == n else { throw InputError.unsupportedShape }
        return .init(distribution: .init(counts: counts.matrix.elements,mean: mean.matrix.elements,
            covariance: try covariance.matrix.rowValues(),updateTime: time),schemaAccepted: true)
    }
    static func encodeGaussianData(_ distribution: ReferenceGaussianPooling.Distribution) throws -> [String: Value] {
        let counts = try Matrix.fromRows(distribution.counts.isEmpty ? [] : [distribution.counts])
        let mean = try Matrix.fromRows(distribution.mean.isEmpty ? [] : [distribution.mean])
        let covariance = try Matrix.fromRows(distribution.covariance)
        return ["updateTime":.number(Double(Int32(bitPattern: distribution.updateTime))),
                "numberOfEpochs":matrixValue(counts),"covariance":matrixValue(covariance),"average":matrixValue(mean)]
    }
    static func decodeGaussianAlgebra(_ object: [String: Value], maximumElements: Int) throws -> GaussianAlgebraResult {
        guard Set(object.keys) == Set(["classRefId","gaussianData"]),
              case .number = object["classRefId"], case .array(let data) = object["gaussianData"] else {
            return .init(entry: nil,schemaAccepted: false,rejectedDistributionIndices: [])
        }
        let id = try integer(object["classRefId"]!)
        var distributions: [ReferenceGaussianPooling.Distribution] = [], rejected: [Int] = []
        for (index,value) in data.enumerated() {
            let decoded = try decodeGaussianData(objectValue(value),maximumElements: maximumElements)
            if decoded.schemaAccepted, let distribution = decoded.distribution { distributions.append(distribution) }
            else { rejected.append(index) }
        }
        return .init(entry: .init(classReferenceID: id,distributions: distributions),schemaAccepted: true,
                     rejectedDistributionIndices: rejected)
    }
    static func encodeGaussianAlgebra(_ entry: ReferenceTrainingBank.ClassEntry) throws -> [String: Value] {
        ["classRefId":.number(Double(entry.classReferenceID)),
         "gaussianData":.array(try entry.distributions.map { .object(try encodeGaussianData($0)) })]
    }

    private static func objectValue(_ value: Value) -> [String: Value] {
        if case .object(let object) = value { return object }
        return [:] // Qt toObject on a nonobject.
    }
    private static func integer(_ value: Value) throws -> Int32 {
        guard case .number(let number) = value else { return 0 }
        guard number.isFinite, number.rounded(.towardZero) == number,
              number >= Double(Int32.min), number <= Double(Int32.max) else {
            throw InputError.unsupportedInteger
        }
        return Int32(number)
    }
    private static func weightMeanVariances(_ object: [String: Value], maximumElements: Int)
        throws -> (WeightMeanVariances, Bool) {
        guard Set(object.keys) == Set(["weight","mean","variances"]),
              case .object(let weight) = object["weight"],
              case .object(let mean) = object["mean"],
              case .array(let varianceValues) = object["variances"] else {
            return (.init(weight: .empty, mean: .empty, variances: []), false)
        }
        // Vendor fills ordered variance entries before the two other matrices.
        let variances = try varianceValues.map {
            try decodeMatrix(objectValue($0), maximumElements: maximumElements)
        }
        let w = try decodeMatrix(weight, maximumElements: maximumElements)
        let m = try decodeMatrix(mean, maximumElements: maximumElements)
        return (.init(weight: w.matrix, mean: m.matrix, variances: variances.map(\.matrix)),
                w.schemaAccepted && m.schemaAccepted && variances.allSatisfy(\.schemaAccepted))
    }

    static func decodeClassifier(_ object: [String: Value], maximumElements: Int) throws -> ClassifierResult {
        let matrixKeys = ["uniqueFeatureIndices","coeff","pcMeans","eigenvec","meanTot","channelInUse"]
        let keys = matrixKeys + ["weightMeanVariances","classRefIDs","numOfValidFeatures","useCount"]
        guard Set(object.keys) == Set(keys),
              case .array(let wmvs) = object["weightMeanVariances"],
              case .array(let ids) = object["classRefIDs"],
              case .number = object["numOfValidFeatures"], case .number = object["useCount"],
              matrixKeys.allSatisfy({ if case .object = object[$0] { return true }; return false }) else {
            return .init(classifier: nil, schemaAccepted: false)
        }
        let weights = try wmvs.map { try weightMeanVariances(objectValue($0), maximumElements: maximumElements) }
        let classIDs = try ids.map(integer)
        let matrices = try matrixKeys.map { try decodeMatrix(objectValue(object[$0]!), maximumElements: maximumElements) }
        let indices = try unsignedVector(matrices[0].matrix)
        let result = Classifier(weightMeanVariances: weights.map { $0.0 }, classRefIDs: classIDs,
            uniqueFeatureIndices: indices, coeff: matrices[1].matrix, pcMeans: matrices[2].matrix,
            eigenvec: matrices[3].matrix, meanTot: matrices[4].matrix, channelInUse: matrices[5].matrix,
            numOfValidFeatures: storedClassifierCount(decodedQtInt: try integer(object["numOfValidFeatures"]!)),
            useCount: storedClassifierCount(decodedQtInt: try integer(object["useCount"]!)))
        return .init(classifier: result, schemaAccepted: weights.allSatisfy { $0.1 } && matrices.allSatisfy(\.schemaAccepted))
    }

    /// Independent typed envelope for the proven small-count interchange domain.
    /// No JSON bytes, compression, encryption or runtime-shape validation is claimed.
    static func encodeClassifier(_ classifier: Classifier) throws -> [String: Value] {
        guard classifier.numOfValidFeatures <= UInt64(Int32.max), classifier.useCount <= UInt64(Int32.max) else {
            throw InputError.unsupportedCountRoundTrip
        }
        func matrix(_ matrix: Matrix) -> Value {
            .object(["rows":.number(Double(matrix.rows)),"cols":.number(Double(matrix.columns)),
                     "elements":.array(matrix.elements.map(Value.number))])
        }
        guard classifier.uniqueFeatureIndices.allSatisfy({ $0 <= 9_007_199_254_740_991 }) else {
            throw InputError.unsupportedUnsignedVector
        }
        let indices = classifier.uniqueFeatureIndices.isEmpty ? Matrix.empty : Matrix(
            rows: classifier.uniqueFeatureIndices.count, columns: 1,
            elements: classifier.uniqueFeatureIndices.map { Double($0) })
        return ["weightMeanVariances":.array(classifier.weightMeanVariances.map {
            .object(["weight":matrix($0.weight),"mean":matrix($0.mean),"variances":.array($0.variances.map(matrix))])
        }),"classRefIDs":.array(classifier.classRefIDs.map { .number(Double($0)) }),
        "uniqueFeatureIndices":matrix(indices),"coeff":matrix(classifier.coeff),"pcMeans":matrix(classifier.pcMeans),
        "eigenvec":matrix(classifier.eigenvec),"meanTot":matrix(classifier.meanTot),"channelInUse":matrix(classifier.channelInUse),
        "numOfValidFeatures":.number(Double(classifier.numOfValidFeatures)),"useCount":.number(Double(classifier.useCount))]
    }

    /// Exact keys/types, followed by a deliberately finite integer dimension domain.
    /// Vendor exceptional cases become explicit errors, never successful empty data.
    static func decodeMatrix(_ object: [String: Value], maximumElements: Int) throws -> MatrixResult {
        guard Set(object.keys) == Set(["rows", "cols", "elements"]),
              case .number(let rowValue) = object["rows"],
              case .number(let columnValue) = object["cols"],
              case .array(let values) = object["elements"] else {
            return MatrixResult(matrix: .empty, schemaAccepted: false)
        }
        guard rowValue.isFinite, columnValue.isFinite,
              rowValue >= 0, columnValue >= 0,
              rowValue <= Double(Int32.max), columnValue <= Double(Int32.max),
              rowValue.rounded(.towardZero) == rowValue,
              columnValue.rounded(.towardZero) == columnValue else {
            throw InputError.unsupportedDimensions
        }
        let rows = Int(rowValue), columns = Int(columnValue)
        guard maximumElements >= 0 else { throw InputError.resourceLimit }
        if rows == 0 || columns == 0 {
            guard rows == 0, columns == 0, values.isEmpty else { throw InputError.unsupportedShape }
            return MatrixResult(matrix: .empty, schemaAccepted: true)
        }
        let (count, overflow) = rows.multipliedReportingOverflow(by: columns)
        guard !overflow, count <= maximumElements else { throw InputError.resourceLimit }
        guard !values.isEmpty, values.count <= count else { throw InputError.unsupportedShape }
        var elements = Array(repeating: 0.0, count: count)
        for (index, value) in values.enumerated() {
            if case .number(let number) = value {
                guard number.isFinite else { throw InputError.nonfiniteElement }
                elements[index] = number
            } // concreteDouble(default 0): other JSON kinds become zero.
        }
        return MatrixResult(matrix: Matrix(rows: rows, columns: columns, elements: elements),
                            schemaAccepted: true)
    }

    /// The Matrix→arma::uvec bridge accepts a row OR column vector; output is a column.
    /// Restrict conversion to finite nonnegative exactly representable integers.
    static func unsignedVector(_ matrix: Matrix) throws -> [UInt64] {
        if matrix == .empty { return [] }
        let (count, overflow) = matrix.rows.multipliedReportingOverflow(by: matrix.columns)
        guard matrix.rows == 1 || matrix.columns == 1,
              matrix.rows > 0, matrix.columns > 0, !overflow,
              matrix.elements.count == count else {
            throw InputError.unsupportedUnsignedVector
        }
        return try matrix.elements.map { value in
            guard value.isFinite, value >= 0, value <= 9_007_199_254_740_991,
                  value.rounded(.towardZero) == value else { throw InputError.unsupportedUnsignedVector }
            return UInt64(value)
        }
    }

    /// Actual signed32→SXTW→unsigned64 storage. Qt JSON→Int edge behavior is external.
    static func storedClassifierCount(decodedQtInt: Int32) -> UInt64 {
        UInt64(bitPattern: Int64(decodedQtInt))
    }

    /// Independent deterministic byte policy, not a claim of identical Qt JSON bytes.
    static func encodeJSONObject(_ object: [String: Value], maximumBytes: Int, maximumNesting: Int) throws -> Data {
        guard maximumBytes >= 0, maximumNesting >= 0 else { throw InputError.resourceLimit }
        func convert(_ value: Value, depth: Int) throws -> Any {
            guard depth <= maximumNesting else { throw InputError.nestingLimit }
            switch value {
            case .number(let number):
                guard number.isFinite else { throw InputError.nonfiniteElement }; return NSNumber(value: number)
            case .bool(let flag): return NSNumber(value: flag)
            case .string(let string): return string
            case .null: return NSNull()
            case .array(let values): return try values.map { try convert($0,depth: depth + 1) }
            case .object(let object): return try object.mapValues { try convert($0,depth: depth + 1) }
            }
        }
        let bytes = try JSONSerialization.data(withJSONObject: convert(.object(object),depth: 0), options: [.sortedKeys])
        guard bytes.count <= maximumBytes else { throw InputError.resourceLimit }
        return bytes
    }
    static func decodeJSONObject(_ bytes: Data, maximumBytes: Int, maximumNesting: Int) throws -> [String: Value] {
        guard maximumBytes >= 0, maximumNesting >= 0, bytes.count <= maximumBytes else { throw InputError.resourceLimit }
        func convert(_ value: Any, depth: Int) throws -> Value {
            guard depth <= maximumNesting else { throw InputError.nestingLimit }
            if value is NSNull { return .null }
            if let number = value as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
                guard number.doubleValue.isFinite else { throw InputError.nonfiniteElement }
                return .number(number.doubleValue)
            }
            if let string = value as? String { return .string(string) }
            if let array = value as? [Any] { return .array(try array.map { try convert($0,depth: depth + 1) }) }
            if let object = value as? [String: Any] { return .object(try object.mapValues { try convert($0,depth: depth + 1) }) }
            throw InputError.invalidJSON
        }
        let raw = try JSONSerialization.jsonObject(with: bytes)
        guard case .object(let object) = try convert(raw,depth: 0) else { throw InputError.invalidJSON }
        return object
    }
}
