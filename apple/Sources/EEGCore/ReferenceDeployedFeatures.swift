import Foundation

/// Comparison-only deployed band-feature and validity branches. Coordinates,
/// bands and quality values must come from an explicit reference configuration.
/// This does not reconstruct that configuration or enable live commands.
enum ReferenceDeployedFeatures {
    enum InputError: Error, Equatable { case invalidShape, invalidCoordinate, invalidPower, nonFinite }
    struct Coordinate: Equatable {
        let row: Int
        let band: Int
    }
    enum Feature: Equatable {
        case power(Coordinate)
        case ratio(numerator: Coordinate, denominator: Coordinate)
    }

    /// Classification constructs BandRatioTxf with mode 1 in both branches:
    /// power = 10 log10(P); ratio = 10 log10(Pnum/Pden). Order and repeats survive.
    static func extract(channelBands: [[Double]], features: [Feature]) throws -> [Double] {
        guard let width = channelBands.first?.count, width > 0,
              channelBands.allSatisfy({ $0.count == width }) else { throw InputError.invalidShape }
        func value(_ coordinate: Coordinate) throws -> Double {
            guard channelBands.indices.contains(coordinate.row),
                  (0..<width).contains(coordinate.band) else { throw InputError.invalidCoordinate }
            let result = channelBands[coordinate.row][coordinate.band]
            // Explicit finite-positive support boundary; vendor log has no floor.
            guard result.isFinite, result > 0 else { throw InputError.invalidPower }
            return result
        }
        return try features.map { feature in
            let power: Double
            switch feature {
            case .power(let coordinate): power = try value(coordinate)
            case .ratio(let numerator, let denominator): power = try value(numerator) / value(denominator)
            }
            let result = 10 * log10(power)
            guard result.isFinite else { throw InputError.nonFinite }
            return result
        }
    }

    /// Default headset branch of isCurrentEpochClean: overallCQ >= 50.
    /// Input retains the vendor's numeric scale, not an assumed 0...1 proportion.
    static func overallContactIsClean(_ quality: Double) -> Bool { quality >= 50 }

    /// Manager skips computation only for an empty classifier, inactive training,
    /// and control other than 1. Empty epochs separately suppress feature creation.
    static func shouldComputeFeatures(classifierEmpty: Bool, trainingActive: Bool,
                                      trainingControl: Int, epochEmpty: Bool) -> Bool {
        !epochEmpty && (!classifierEmpty || trainingActive || trainingControl == 1)
    }
}

/// Training background subtraction updates its own state from clean features.
/// Detection continues to receive the original feature vector (manager run).
struct ReferenceTrainingBackground {
    private(set) var mean: [Double] = []
    private(set) var count: Int = 0

    mutating func reset() { mean = []; count = 0 }

    /// First update initializes the mean; later updates cap the old count at479.
    /// Thereafter mean=(479*mean+x)/480, rather than a finite rolling window.
    mutating func process(_ features: [Double]) throws -> [Double] {
        guard !features.isEmpty else { return [] }
        guard features.allSatisfy(\.isFinite) else { throw ReferenceDeployedFeatures.InputError.nonFinite }
        guard mean.isEmpty || mean.count == features.count else {
            throw ReferenceDeployedFeatures.InputError.invalidShape
        }
        let old = min(count, 479)
        let previous = mean.isEmpty ? features : mean
        let updated = zip(previous, features).map { (Double(old) * $0 + $1) / Double(old + 1) }
        let output = zip(features, updated).map(-)
        guard updated.allSatisfy(\.isFinite), output.allSatisfy(\.isFinite) else {
            throw ReferenceDeployedFeatures.InputError.nonFinite
        }
        mean = updated; count = old + 1
        return output
    }
}
