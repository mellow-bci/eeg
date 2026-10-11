import XCTest
@testable import EEGCore

final class ReferenceInverseDispatchTests: XCTestCase {
    typealias D = ReferenceInverseDispatch
    private func matrix(_ n: Int, diagonal: Double = 2) -> [Double] {
        var a = [Double](repeating: 0, count: n*n)
        for i in 0..<n { a[i*n+i] = diagonal }
        return a
    }
    private func route(_ a: [Double], _ n: Int = 5) throws -> D.Route {
        try D.route(columnMajor: a, dimension: n, maximumDimension: 70)
    }
    func testDispatcherOrderAndExactTriangularZeros() throws {
        XCTAssertEqual(try route(matrix(2),2), .smallFormula(2))
        XCTAssertEqual(try route(matrix(5)), .diagonal)
        var a = matrix(5); a[5] = 0.3
        XCTAssertEqual(try route(a), .upperTriangular)
        a[1] = Double.leastNonzeroMagnitude
        XCTAssertEqual(try route(a), .generalLU) // asymmetry, not rounded to zero
        a[5] = 0
        XCTAssertEqual(try route(a), .lowerTriangular)
        XCTAssertThrowsError(try route([.nan],1))
    }
    func testPositiveDefiniteHeuristicStrictBoundariesAndNotProof() throws {
        var a = matrix(5); a[1] = 0.5; a[5] = 0.5
        XCTAssertEqual(try route(a), .positiveDefiniteCandidate)
        a[1] = 2; a[5] = 2
        XCTAssertEqual(try route(a), .generalLU) // equal largest diagonal fails
        // Pair sum boundary is reached while lower magnitude is below max diagonal.
        a = matrix(5); a[0] = 1; a[6] = 1; a[1] = 1; a[5] = 1
        XCTAssertEqual(try route(a), .generalLU)
        a[1] = 1.nextDown; a[5] = 1.nextDown
        XCTAssertEqual(try route(a), .positiveDefiniteCandidate)
        // All pair heuristics pass, although this matrix is indefinite.
        a = [Double](repeating: -0.5, count: 25)
        for i in 0..<5 { a[i*5+i] = 1 }
        XCTAssertEqual(try route(a), .positiveDefiniteCandidate)
    }
    func testAbsoluteAndRelativeSymmetryTolerance() throws {
        var a = matrix(5); a[1] = 0.5; a[5] = 0.5 + D.symmetryTolerance
        XCTAssertEqual(try route(a), .positiveDefiniteCandidate)
        a[5] = (0.5 + D.symmetryTolerance).nextUp
        XCTAssertEqual(try route(a), .generalLU)
        a = matrix(5,diagonal: 100); a[1] = 10; a[5] = 10 + D.symmetryTolerance * 5
        XCTAssertEqual(try route(a), .positiveDefiniteCandidate)
        a[5] = 10 + D.symmetryTolerance * 11
        XCTAssertEqual(try route(a), .generalLU)
    }
    func testSmallDeterminantBoundaryDoesNotMeanSingular() throws {
        let t = D.smallDeterminantThreshold
        XCTAssertNotNil(try D.smallTwoByTwo(columnMajor: [1,0,0,t]))
        XCTAssertNil(try D.smallTwoByTwo(columnMajor: [1,0,0,t.nextDown]))
        XCTAssertNotNil(try D.smallTwoByTwo(columnMajor: [1,0,0,-t]))
        XCTAssertNil(try D.smallTwoByTwo(columnMajor: [1,1,1,1]))
        let inverse = try XCTUnwrap(D.smallTwoByTwo(columnMajor: [2,1,3,4]))
        XCTAssertEqual(inverse,[0.8,-0.2,-0.6,0.4])
    }
    func testTriangularLeafResidualAndUnusedTriangleClearing() throws {
        for lower in [true,false] {
            let a: [Double] = lower ? [2,1,99,4] : [2,99,1,4]
            let inverse = try D.triangularInverse(columnMajor:a, dimension:2, lower:lower, maximumDimension:70)
            XCTAssertEqual(inverse, lower ? [0.5,-0.125,0,0.25] : [0.5,0,-0.125,0.25])
        }
        XCTAssertThrowsError(try D.triangularInverse(columnMajor:[0,0,0,1],dimension:2,lower:true,maximumDimension:70))
    }
    private func assertResidual(_ a:[Double], _ b:[Double], _ n:Int, file:StaticString = #filePath, line:UInt = #line) {
        for r in 0..<n { for c in 0..<n {
            let product = (0..<n).reduce(0.0) { $0 + a[$1*n+r]*b[c*n+$1] }
            XCTAssertEqual(product,r == c ? 1:0,accuracy:1e-11,file:file,line:line)
        } }
    }
    func testCompositionFallbacksAndUnsupportedSmallFormula() throws {
        let tiny = [1.0,0,0,D.smallDeterminantThreshold.nextDown]
        let small = try D.inverse(columnMajor:tiny,dimension:2,maximumDimension:70)
        XCTAssertEqual(small.attemptedRoutes,[.smallFormula(2),.generalLU]); assertResidual(tiny,small.columnMajor,2)
        var indefinite = [Double](repeating:-0.5,count:25)
        for i in 0..<5 { indefinite[i*5+i] = 1 }
        let fallback = try D.inverse(columnMajor:indefinite,dimension:5,maximumDimension:70)
        XCTAssertEqual(fallback.attemptedRoutes,[.positiveDefiniteCandidate,.generalLU]); assertResidual(indefinite,fallback.columnMajor,5)
        assertResidual(matrix(4),try D.inverse(columnMajor:matrix(4),dimension:4,maximumDimension:70).columnMajor,4)
        XCTAssertThrowsError(try D.inverse(columnMajor:[1,1,1,1],dimension:2,maximumDimension:70))
    }
    func testCompositionSPDAndQuerySizedGeneralInverse() throws {
        var a = matrix(5); a[1] = 0.5; a[5] = 0.5
        let spd = try D.inverse(columnMajor:a,dimension:5,maximumDimension:70)
        XCTAssertEqual(spd.attemptedRoutes,[.positiveDefiniteCandidate]); assertResidual(a,spd.columnMajor,5)
        a = matrix(17); a[1] = 0.1; a[17] = 0.2
        let lu = try D.inverse(columnMajor:a,dimension:17,maximumDimension:70)
        XCTAssertEqual(lu.attemptedRoutes,[.generalLU]); assertResidual(a,lu.columnMajor,17)
    }

    func testThreeByThreeCompositionAndThresholdFallback() throws {
        let a = [3.0,1,2, 2,4,1, 1,2,5]
        let result = try D.inverse(columnMajor:a,dimension:3,maximumDimension:70)
        XCTAssertEqual(result.attemptedRoutes,[.smallFormula(3)]); assertResidual(a,result.columnMajor,3)
        var tiny = matrix(3,diagonal:1); tiny[8] = D.smallDeterminantThreshold.nextDown
        let fallback = try D.inverse(columnMajor:tiny,dimension:3,maximumDimension:70)
        XCTAssertEqual(fallback.attemptedRoutes,[.smallFormula(3),.generalLU]); assertResidual(tiny,fallback.columnMajor,3)
    }

    func testFourByFourScalarOrderResidualsAndLUBoundaryFallback() throws {
        // Nonsymmetric, well-conditioned authored inputs, not model assets.
        for seed in 1...40 {
            var a = (0..<16).map { Double((($0+3)*seed*7)%19-9)/20 }
            for i in 0..<4 { a[i*4+i] += 3 }
            let result = try D.inverse(columnMajor:a,dimension:4,maximumDimension:70)
            XCTAssertEqual(result.attemptedRoutes,[.smallFormula(4)])
            assertResidual(a,result.columnMajor,4)
        }
        var tiny = matrix(4,diagonal:1); tiny[15] = D.smallDeterminantThreshold.nextDown
        let fallback = try D.inverse(columnMajor:tiny,dimension:4,maximumDimension:70)
        XCTAssertEqual(fallback.attemptedRoutes,[.smallFormula(4),.generalLU]); assertResidual(tiny,fallback.columnMajor,4)
        tiny[15] = D.smallDeterminantThreshold
        XCTAssertEqual(try D.inverse(columnMajor:tiny,dimension:4,maximumDimension:70).attemptedRoutes,[.smallFormula(4)])
    }

}
