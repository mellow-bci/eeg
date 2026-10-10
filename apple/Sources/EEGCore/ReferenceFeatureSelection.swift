import Foundation

/// Bounded reconstruction of runUnivCoordSelection; comparison-only, never a
/// replacement for the qualified acquisition or existing runtime profile path.
/// Evidence: feature-selection-continuation and training-followup-20261010.
enum ReferenceFeatureSelection {
    enum InputError: Error, Equatable {
        case invalidShape, invalidValue, insufficientEpochs, ambiguousCutoffTie
    }

    struct ClassStatistics: Sendable {
        let mean: [Double]
        /// Diagonal of the already fitted covariance. Off-diagonal entries do
        /// not enter this ranking stage, but remain necessary for later fitting.
        let variance: [Double]
        let epochCounts: [Double]
    }

    struct Result: Sendable {
        let scoresByClass: [[Double]]
        let rankedCoordinatesByClass: [[Int]]
        let perClassBudget: Int
        /// Sorted union, suitable for common covariance/mean coordinate slicing.
        let selectedCoordinates: [Int]
    }

    static let minimumEpochs = 20.0 // inclusive, body 0x100b43814–0x100b43918
    static let denominatorEpsilon = Double(bitPattern: 0x3ce4000000000000)

    static func select(_ classes: [ClassStatistics]) throws -> Result {
        guard classes.count >= 2, let width = classes.first?.mean.count, width > 0,
              classes.allSatisfy({ $0.mean.count == width && $0.variance.count == width && $0.epochCounts.count == width })
        else { throw InputError.invalidShape }
        guard classes.allSatisfy({ c in
            c.mean.allSatisfy(\.isFinite) && c.variance.allSatisfy({ $0.isFinite && $0 >= 0 }) &&
                c.epochCounts.allSatisfy({ $0.isFinite && $0 >= 0 })
        }) else { throw InputError.invalidValue }

        let eligible = classes.map { $0.epochCounts.map { $0 >= minimumEpochs } }
        guard (0..<width).contains(where: { f in eligible.contains(where: { $0[f] }) })
        else { throw InputError.insufficientEpochs }

        let budget = try coordinateBudget(epochCounts: classes.map(\.epochCounts))

        var scores = [[Double]]()
        var rankings = [[Int]]()
        var selected = Set<Int>()
        for i in classes.indices {
            var row = [Double](repeating: .infinity, count: width)
            for j in classes.indices where j != i {
                for f in 0..<width {
                    // Deliberately class-i normalization, not pooled variance.
                    // Divide first, then multiply by the joint eligibility mask.
                    let separation = abs(classes[i].mean[f] - classes[j].mean[f]) /
                        (sqrt(classes[i].variance[f]) + denominatorEpsilon)
                    let score = separation * (eligible[i][f] && eligible[j][f] ? 1 : 0)
                    guard score.isFinite else { throw InputError.invalidValue }
                    if score < row[f] { row[f] = score }
                }
            }
            let order = row.indices.sorted { row[$0] == row[$1] ? $0 < $1 : row[$0] > row[$1] }
            // No unproven emulation of vendor std::sort tie permutations.
            if budget < width, row[order[budget - 1]] == row[order[budget]] {
                throw InputError.ambiguousCutoffTie
            }
            scores.append(row)
            rankings.append(order)
            selected.formUnion(order.prefix(budget))
        }
        return Result(scoresByClass: scores, rankedCoordinatesByClass: rankings,
                      perClassBudget: budget, selectedCoordinates: selected.sorted())
    }

    static func coordinateBudget(epochCounts: [[Double]]) throws -> Int {
        guard epochCounts.count >= 2, let width = epochCounts.first?.count, width > 0,
              epochCounts.allSatisfy({ $0.count == width }) else { throw InputError.invalidShape }
        guard epochCounts.flatMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw InputError.invalidValue }
        let eligible = epochCounts.map { $0.map { $0 >= minimumEpochs } }
        guard (0..<width).contains(where: { f in eligible.contains(where: { $0[f] }) })
        else { throw InputError.insufficientEpochs }
        // Numerator sums ALL counts, including counts below 20; denominator
        // sums the eligible-class flags. No masking of the numerator is present.
        var minimumRatio = Double.infinity
        for f in 0..<width {
            let count = epochCounts.reduce(0.0) { $0 + $1[f] }
            let validClassCount = eligible.reduce(0) { $0 + ($1[f] ? 1 : 0) }
            let ratio = count / Double(validClassCount)
            if ratio < minimumRatio { minimumRatio = ratio }
        }
        let root = ceil(sqrt(2 * minimumRatio))
        guard root.isFinite, root > 0 else { throw InputError.invalidValue }
        return root >= Double(width) ? width : Int(root)
    }
}
