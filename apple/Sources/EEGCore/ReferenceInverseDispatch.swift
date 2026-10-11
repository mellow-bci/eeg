import Accelerate
import Foundation

/// Finite, bounded comparison adapter for the inverse dispatcher at 0x100b57690.
/// This is not a replacement for the whole vendor inverse implementation.
enum ReferenceInverseDispatch {
    enum Failure: Error { case invalidInput, resourceLimit, lapack(Int32), nonfiniteOutput }
    enum Route: Equatable {
        case smallFormula(Int), diagonal, upperTriangular, lowerTriangular, positiveDefiniteCandidate, generalLU
    }
    static let smallDeterminantThreshold = Double(bitPattern: 0x3cb0000000000000)
    static let symmetryTolerance = Double(bitPattern: 0x3d19000000000000)

    private static func validate(_ matrix: [Double], _ n: Int, _ limit: Int) throws {
        // Our allocation policy, not a recovered vendor maximum.
        guard limit > 0, limit <= 4096, n > 0, n <= limit else { throw Failure.resourceLimit }
        guard matrix.count == n * n, matrix.allSatisfy(\.isFinite) else { throw Failure.invalidInput }
    }

    /// Column-major input. The SPD result is only a heuristic: failed Cholesky
    /// must still fall through to general LU in a complete inverse caller.
    static func route(columnMajor a: [Double], dimension n: Int, maximumDimension: Int) throws -> Route {
        try validate(a, n, maximumDimension)
        if n <= 4 { return .smallFormula(n) }
        func at(_ row: Int, _ col: Int) -> Double { a[col * n + row] }
        if (0..<n).allSatisfy({ c in (0..<n).allSatisfy({ r in r == c || at(r,c) == 0 }) }) { return .diagonal }
        if (0..<n).allSatisfy({ c in ((c+1)..<n).allSatisfy({ at($0,c) == 0 }) }) { return .upperTriangular }
        if (0..<n).allSatisfy({ c in (0..<c).allSatisfy({ at($0,c) == 0 }) }) { return .lowerTriangular }
        let diagonal = (0..<n).map { at($0,$0) }
        guard diagonal.allSatisfy({ $0 > 0 }), let maxDiagonal = diagonal.max() else { return .generalLU }
        for c in 0..<(n-1) {
            for r in (c+1)..<n {
                let lower = at(r,c), upper = at(c,r), magnitude = abs(lower)
                if magnitude >= maxDiagonal { return .generalLU }
                let difference = abs(lower-upper)
                if difference > symmetryTolerance && difference > max(magnitude,abs(upper)) * symmetryTolerance { return .generalLU }
                if magnitude + magnitude >= diagonal[c] + diagonal[r] { return .generalLU }
            }
        }
        return .positiveDefiniteCandidate
    }

    /// The traced 2x2 shortcut. Nil means the dispatcher must try LU, not that
    /// the matrix is singular. FMA ordering follows 57a14..18 exactly.
    static func smallTwoByTwo(columnMajor a: [Double]) throws -> [Double]? {
        try validate(a, 2, 2)
        let determinant = (-(a[2] * a[1])).addingProduct(a[0], a[3])
        if abs(determinant) < smallDeterminantThreshold { return nil }
        let result = [a[3]/determinant, -a[1]/determinant, -a[2]/determinant, a[0]/determinant]
        // Vendor leaf lacks this guard. Our wrapper exposes overflow as failure.
        guard determinant.isFinite, result.allSatisfy(\.isFinite) else { throw Failure.nonfiniteOutput }
        return result
    }

    /// 3x3 determinant expansion and cofactors retain the traced rounded
    /// products/FMA order (58bd4..c14 and 57fc4..580d8).
    static func smallThreeByThree(columnMajor a:[Double]) throws -> [Double]? {
        try validate(a,3,3)
        let term1 = (-(a[5]*a[7])).addingProduct(a[8],a[4]) * a[0]
        let term2 = (-(a[5]*a[6])).addingProduct(a[8],a[3]) * a[1]
        let term3 = (-(a[4]*a[6])).addingProduct(a[7],a[3]) * a[2]
        let det = term3 + (term1-term2)
        if abs(det) < smallDeterminantThreshold { return nil }
        // fnmadd = -(product + addend), retaining its single rounding.
        let result = [
            (-(a[5]*a[7])).addingProduct(a[8],a[4])/det,
            -(-(a[2]*a[7])).addingProduct(a[8],a[1])/det,
            (-(a[2]*a[4])).addingProduct(a[5],a[1])/det,
            -(-(a[5]*a[6])).addingProduct(a[8],a[3])/det,
            (-(a[2]*a[6])).addingProduct(a[8],a[0])/det,
            -(-(a[2]*a[3])).addingProduct(a[5],a[0])/det,
            (-(a[4]*a[6])).addingProduct(a[7],a[3])/det,
            -(-(a[1]*a[6])).addingProduct(a[7],a[0])/det,
            (-(a[1]*a[3])).addingProduct(a[4],a[0])/det
        ]
        guard det.isFinite, result.allSatisfy(\.isFinite) else { throw Failure.nonfiniteOutput }
        let check = (result[1]*a[3]).addingProduct(a[0],result[0]).addingProduct(a[6],result[2])
        return abs(1-check) < 1e-10 ? result : nil
    }

    struct Inverse {
        let columnMajor: [Double]
        let attemptedRoutes: [Route]
    }
    /// Bounded inverse composition; all fallback starts from original input.
    static func inverse(columnMajor input: [Double], dimension n: Int, maximumDimension: Int) throws -> Inverse {
        let initial = try route(columnMajor: input, dimension: n, maximumDimension: maximumDimension)
        var attempts = [initial]
        func finished(_ a: [Double]) throws -> Inverse {
            guard a.allSatisfy(\.isFinite) else { throw Failure.nonfiniteOutput }
            return .init(columnMajor:a,attemptedRoutes:attempts)
        }
        switch initial {
        case .smallFormula(1): return try finished([1/input[0]])
        case .smallFormula(2):
            if let a = try smallTwoByTwo(columnMajor:input) { return try finished(a) }
        case .smallFormula(3):
            if let a = try smallThreeByThree(columnMajor:input) { return try finished(a) }
        case .smallFormula(4):
            if let a = ReferenceSmallFourInverse.attempt(input) { return try finished(a) }
        case .smallFormula: throw Failure.invalidInput
        case .diagonal:
            var a = [Double](repeating:0,count:n*n)
            for i in 0..<n { guard input[i*n+i] != 0 else { throw Failure.lapack(Int32(i+1)) }; a[i*n+i] = 1/input[i*n+i] }
            return try finished(a)
        case .upperTriangular, .lowerTriangular:
            return try finished(triangularInverse(columnMajor:input,dimension:n,lower:initial == .lowerTriangular,maximumDimension:maximumDimension))
        case .positiveDefiniteCandidate:
            var a = input, size = Int32(n), lda = Int32(n), info:Int32 = 0, lower:Int8 = 76
            dpotrf_(&lower,&size,&a,&lda,&info)
            if info == 0 {
                dpotri_(&lower,&size,&a,&lda,&info)
                if info == 0 {
                    for c in 0..<n { for r in 0..<c { a[c*n+r] = a[r*n+c] } }
                    return try finished(a)
                }
            }
        case .generalLU: break
        }
        if initial != .generalLU { attempts.append(.generalLU) }
        return try finished(generalInverse(input,n))
    }
    private static func generalInverse(_ input:[Double], _ n:Int) throws -> [Double] {
        var a = input, size = Int32(n), lda = Int32(n), info:Int32 = 0
        var pivots = [Int32](repeating:0,count:n), workCount = Int32(max(n,16))
        // The vendor queries only n>16, before factorization (58a10).
        if n > 16 {
            var query = [0.0], queryCount:Int32 = -1
            dgetri_(&size,&a,&lda,&pivots,&query,&queryCount,&info)
            guard info == 0 else { throw Failure.lapack(info) }
            guard query[0].isFinite, query[0] >= 1, query[0] <= Double(Int32.max), query[0] <= 16_777_216 else { throw Failure.resourceLimit }
            workCount = max(workCount,Int32(query[0]))
        }
        var work = [Double](repeating:0,count:Int(workCount))
        var rows = size
        dgetrf_(&rows,&size,&a,&lda,&pivots,&info)
        guard info == 0 else { throw Failure.lapack(info) }
        dgetri_(&size,&a,&lda,&pivots,&work,&workCount,&info)
        guard info == 0 else { throw Failure.lapack(info) }
        return a
    }

    /// Explicit triangular leaf 0x100b58344, for callers already holding a
    /// triangular factor. This bypasses the small-formula dispatcher by design.
    /// The unused input triangle is ignored and zeroed in the returned matrix.
    static func triangularInverse(columnMajor input: [Double], dimension n: Int,
                                  lower: Bool, maximumDimension: Int) throws -> [Double] {
        try validate(input, n, maximumDimension)
        var matrix = input
        var size = Int32(n), lda = Int32(n), info: Int32 = 0
        var triangle: Int8 = lower ? 76 : 85, diagonal: Int8 = 78
        dtrtri_(&triangle, &diagonal, &size, &matrix, &lda, &info)
        guard info == 0 else { throw Failure.lapack(info) }
        for c in 0..<n { for r in 0..<n where lower ? r < c : r > c { matrix[c*n+r] = 0 } }
        guard matrix.allSatisfy(\.isFinite) else { throw Failure.nonfiniteOutput }
        return matrix
    }
}
