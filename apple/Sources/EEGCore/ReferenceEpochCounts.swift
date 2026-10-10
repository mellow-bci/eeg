import Foundation

/// Static-body-derived count operations for reference Gaussian training.
/// Threshold extraction is a Cartesian indexed submatrix, not a masked flatten.
enum ReferenceEpochCounts {
    struct Extraction: Equatable {
        let rowIndices: [Int]
        let columnIndices: [Int]
        let values: [[Double]]
    }

    enum CountError: Error, Equatable {
        case invalidShape
        case invalidCount
        case noQualifyingCounts
        case nonFiniteReduction
        case capacityExceeded
    }

    static func extractGreaterThan(_ counts: [[Double]], threshold: Double,
                                   maximumCartesianCells: Int) throws -> Extraction {
        guard maximumCartesianCells >= 0 else { throw CountError.capacityExceeded }
        let columns = try validate(counts, threshold: threshold)
        var qualifyingCount = 0
        for row in counts {
            for value in row where value > threshold {
                let next = qualifyingCount.addingReportingOverflow(1)
                guard !next.overflow else { throw CountError.capacityExceeded }
                qualifyingCount = next.partialValue
            }
        }
        let cells = qualifyingCount.multipliedReportingOverflow(by: qualifyingCount)
        guard !cells.overflow, cells.partialValue <= maximumCartesianCells else {
            throw CountError.capacityExceeded
        }
        var rows: [Int] = []
        var cols: [Int] = []
        rows.reserveCapacity(qualifyingCount)
        cols.reserveCapacity(qualifyingCount)
        // Binary scans row outer, column inner, while source storage is column-major.
        for row in counts.indices {
            for column in 0..<columns where counts[row][column] > threshold {
                rows.append(row)
                cols.append(column)
            }
        }
        // Do not deduplicate indices or gather paired cells: both index vectors
        // are passed to the same Armadillo Cartesian subview helper.
        return .init(rowIndices: rows, columnIndices: cols,
                     values: rows.map { row in cols.map { counts[row][$0] } })
    }

    private static func validate(_ counts: [[Double]], threshold: Double) throws -> Int {
        guard threshold.isFinite else { throw CountError.invalidCount }
        let columns = counts.first?.count ?? 0
        guard counts.allSatisfy({ $0.count == columns }) else { throw CountError.invalidShape }
        guard counts.allSatisfy({ $0.allSatisfy({ $0.isFinite && $0 >= 0 }) }) else {
            throw CountError.invalidCount
        }
        return columns
    }

    /// gaussianTransform extracts >5, applies column mean (dim 0), takes its
    /// first element and repeats it across the transformed mean's dimension.
    /// For a 1×D input this is the first >5 count, not an average across features.
    static func projectedCounts(_ counts: [[Double]], outputDimension: Int) throws -> [Double] {
        guard outputDimension > 0 else { throw CountError.invalidShape }
        let columns = try validate(counts, threshold: 5)
        // Reduction-only equivalent: avoid constructing a K×K temporary when
        // only its first column mean is consumed. Preserve row multiplicities.
        var firstSelectedColumn: Int?
        for row in counts where firstSelectedColumn == nil {
            firstSelectedColumn = row.firstIndex(where: { $0 > 5 })
        }
        guard let firstSelectedColumn else { throw CountError.noQualifyingCounts }
        var sum = 0.0
        var repetitions = 0
        for row in counts {
            for column in 0..<columns where row[column] > 5 {
                sum += row[firstSelectedColumn]
                let next = repetitions.addingReportingOverflow(1)
                guard !next.overflow else { throw CountError.capacityExceeded }
                repetitions = next.partialValue
            }
        }
        let firstColumnMean = sum / Double(repetitions)
        // Finite-domain support policy; vendor mean has an overflow fallback
        // that this bounded implementation does not silently approximate.
        guard firstColumnMean.isFinite else { throw CountError.nonFiniteReduction }
        return Array(repeating: firstColumnMean, count: outputDimension)
    }
}
