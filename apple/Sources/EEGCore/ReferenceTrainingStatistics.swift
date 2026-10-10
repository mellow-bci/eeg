import Foundation

/// Comparison kernel for already accepted feature rows / epoch columns.
/// No upstream windowing, filtering or training acceptance is inferred here.
enum ReferenceTrainingStatistics {
    enum InputError: Error, Equatable { case invalidShape, invalidCoordinates, nonFinite, numericalFailure }
    struct Statistics: Sendable, Equatable {
        let average: [Double]
        let covariance: [[Double]]
        let epochCounts: [Double]
    }

    /// N>=2 excludes the reference covariance helper's singleton-vector reinterpretation.
    /// Coordinates scatter into zeroed F-dimensional outputs with ordered duplicate overwrites.
    static func fit(featureRows: [[Double]], coordinates: [Int], maximumEpochs: Int) throws -> Statistics {
        let dimension = featureRows.count
        guard dimension > 0, dimension <= 70, let epochs = featureRows.first?.count,
              epochs >= 2, maximumEpochs >= 2, epochs <= maximumEpochs,
              featureRows.allSatisfy({ $0.count == epochs }) else { throw InputError.invalidShape }
        guard coordinates.count == dimension,
              coordinates.allSatisfy({ $0 >= 0 && $0 < dimension }) else { throw InputError.invalidCoordinates }
        guard featureRows.allSatisfy({ $0.allSatisfy(\.isFinite) }) else { throw InputError.nonFinite }
        let means = featureRows.map { $0.reduce(0, +) / Double(epochs) }
        guard means.allSatisfy(\.isFinite) else { throw InputError.numericalFailure }
        var sourceCovariance = Array(repeating: Array(repeating: 0.0, count: dimension), count: dimension)
        for column in 0..<dimension {
            for row in 0..<dimension {
                var product = 0.0
                for epoch in 0..<epochs {
                    product += (featureRows[row][epoch] - means[row]) * (featureRows[column][epoch] - means[column])
                }
                let value = product / Double(epochs - 1)
                guard value.isFinite else { throw InputError.numericalFailure }
                sourceCovariance[row][column] = value
            }
        }
        var average = Array(repeating: 0.0, count: dimension)
        var counts = Array(repeating: 0.0, count: dimension)
        var covariance = Array(repeating: Array(repeating: 0.0, count: dimension), count: dimension)
        for source in 0..<dimension {
            average[coordinates[source]] = means[source]
            counts[coordinates[source]] = Double(epochs)
        }
        // The reference assignment visits source columns outside source rows.
        for column in 0..<dimension {
            for row in 0..<dimension {
                covariance[coordinates[row]][coordinates[column]] = sourceCovariance[row][column]
            }
        }
        return Statistics(average: average, covariance: covariance, epochCounts: counts)
    }
}
