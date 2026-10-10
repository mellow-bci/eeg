import Foundation

/// Comparison-only gaussianTransform arithmetic without a scoring-time Cholesky.
/// Singular PSD projection is not a valid Gaussian density or production command.
enum ReferenceGaussianProjection {
    enum ProjectionError: Error { case invalidShape, invalidWeight, nonFiniteResult }

    static func project(_ component: ReferenceGaussianPipeline.Component,
                        basis: [[Double]]) throws -> ReferenceGaussianPipeline.Component {
        _ = try ReferenceTrainingEdgeCases.psdEigenbasis(covariance: component.covariance)
        let result = try arithmetic(component, basis: basis)
        _ = try ReferenceTrainingEdgeCases.psdEigenbasis(covariance: result.covariance)
        return result
    }

    /// Shared arithmetic for PSD fitting and the separately validated density path.
    /// Callers establish their covariance admissibility before and after this step.
    static func arithmetic(_ component: ReferenceGaussianPipeline.Component,
                           basis: [[Double]]) throws -> ReferenceGaussianPipeline.Component {
        let size = component.mean.count
        guard (1...70).contains(size), basis.count == size,
              let outputs = basis.first?.count, (1...70).contains(outputs),
              basis.allSatisfy({ $0.count == outputs }), component.covariance.count == size,
              component.covariance.allSatisfy({ $0.count == size }) else {
            throw ProjectionError.invalidShape
        }
        guard component.weight.isFinite, component.weight >= 0 else { throw ProjectionError.invalidWeight }
        let mean = try ReferenceGaussianPipeline.transform(component.mean,
            using: .init(mean: Array(repeating: 0, count: size), basis: basis))
        var left = Array(repeating: Array(repeating: 0.0, count: size), count: outputs)
        for output in 0..<outputs {
            for column in 0..<size {
                for row in 0..<size {
                    left[output][column] += basis[row][output] * component.covariance[row][column]
                }
            }
        }
        var covariance = Array(repeating: Array(repeating: 0.0, count: outputs), count: outputs)
        for row in 0..<outputs {
            for column in row..<outputs {
                var value = 0.0
                for input in 0..<size { value += left[row][input] * basis[input][column] }
                // Symmetric storage is our floating-point convention. No jitter,
                // diagonal variance floor, inverse or pseudoinverse is inserted.
                covariance[row][column] = value
                covariance[column][row] = value
            }
        }
        guard mean.allSatisfy(\.isFinite), covariance.allSatisfy({ $0.allSatisfy(\.isFinite) }) else {
            throw ProjectionError.nonFiniteResult
        }
        return .init(weight: component.weight, mean: mean, covariance: covariance)
    }
}
