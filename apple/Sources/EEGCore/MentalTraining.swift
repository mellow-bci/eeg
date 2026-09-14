import Foundation
import Accelerate

public enum EEGMentalTraining {
    public enum Failure: Error { case dimensions, decomposition(Int32), numericalFailure }

    /// Independent training recipe. Produces parameters only, not an authorized
    /// profile; provenance serialization and hardware qualification are separate.
    public static func fit(_ records: [EEGTrainingRecord], participantID: String,
                           settings: ProcessingSettings = ProcessingSettings()) throws -> EEGMentalScoringParameters {
        let input = try EEGTrainingData.prepare(records, participantID: participantID, settings: settings)
        let dimensions = min(settings.pcaComponents, records.count - input.classes.count, input.selected.count)
        let components = try principalComponents(input.centeredSelected, count: dimensions)
        let projected = input.centeredSelected.map { row in components.map { component in zip(row, component).reduce(0.0) { $0 + $1.0 * $1.1 } } }
        let gaussians = input.classes.indices.map { c -> EEGMentalScoringParameters.Gaussian in
            let data = projected.indices.filter { input.labels[$0] == c }.map { projected[$0] }
            let mean = (0..<dimensions).map { j in data.reduce(0.0) { $0 + $1[j] } / Double(data.count) }
            let variance = (0..<dimensions).map { j in max(settings.varianceFloor, data.reduce(0.0) { $0 + pow($1[j] - mean[j], 2) } / Double(data.count)) }
            let distances = data.map { row in (0..<dimensions).reduce(0.0) { $0 + pow(row[$1] - mean[$1], 2) / variance[$1] } }.sorted()
            let position = 0.99 * Double(distances.count - 1), lower = Int(floor(position)), upper = Int(ceil(position))
            let quantile = distances[lower] + (position - Double(lower)) * (distances[upper] - distances[lower])
            return .init(label: input.classes[c], mean: mean, variance: variance, distance_limit: max(4 * Double(dimensions), quantile * 1.5))
        }
        guard projected.allSatisfy({ $0.allSatisfy(\.isFinite) }) else { throw Failure.numericalFailure }
        let result = EEGMentalScoringParameters(classes: input.classes, center: input.center, scale: input.scale,
            selected: input.selected, pca_mean: input.pcaMean, components: components, gaussians: gaussians)
        _ = try EEGMentalScoring.score(values: input.center, parameters: result)
        return result
    }

    /// Thin right singular vectors in descending singular-value order.
    /// Sign convention follows Python: largest-magnitude coefficient is positive.
    static func principalComponents(_ rows: [[Double]], count: Int) throws -> [[Double]] {
        guard let width = rows.first?.count, width > 0, width <= 70, !rows.isEmpty,
              rows.count <= Int(Int32.max), count > 0, count <= min(rows.count, width),
              rows.allSatisfy({ $0.count == width && $0.allSatisfy(\.isFinite) }) else { throw Failure.dimensions }
        var m = __LAPACK_int(rows.count), n = __LAPACK_int(width), lda = __LAPACK_int(rows.count)
        var ldu: __LAPACK_int = 1, ldvt = min(m, n), info: __LAPACK_int = 0
        var jobU: Int8 = 78, jobVT: Int8 = 83 // N (no left vectors), S (thin right vectors)
        var matrix = (0..<width).flatMap { j in rows.map { $0[j] } }
        var singular = [Double](repeating: 0, count: Int(ldvt))
        var u = [Double](repeating: 0, count: 1)
        var vt = [Double](repeating: 0, count: Int(ldvt) * width)
        var query = [Double](repeating: 0, count: 1), lwork: __LAPACK_int = -1
        dgesvd_(&jobU, &jobVT, &m, &n, &matrix, &lda, &singular, &u, &ldu, &vt, &ldvt, &query, &lwork, &info)
        guard info == 0 else { throw Failure.decomposition(info) }
        guard query[0].isFinite, query[0] >= 1, query[0] <= Double(Int32.max) else { throw Failure.dimensions }
        lwork = __LAPACK_int(ceil(query[0]))
        var workspace = [Double](repeating: 0, count: Int(lwork))
        dgesvd_(&jobU, &jobVT, &m, &n, &matrix, &lda, &singular, &u, &ldu, &vt, &ldvt, &workspace, &lwork, &info)
        guard info == 0 else { throw Failure.decomposition(info) }
        guard singular.allSatisfy(\.isFinite), vt.allSatisfy(\.isFinite) else { throw Failure.numericalFailure }
        return (0..<count).map { i in
            var row = (0..<width).map { vt[$0 * Int(ldvt) + i] }
            var largest = 0
            for j in 1..<width { if abs(row[j]) > abs(row[largest]) { largest = j } }
            if row[largest] < 0 { row = row.map { -$0 } }
            return row
        }
    }
}
