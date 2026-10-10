import XCTest
@testable import EEGCore

final class ReferenceDateMetadataTests: XCTestCase {
    func testInstalledQtOracleExplicitZoneVectors() throws {
        let vectors = [
            ("2026-10-11T01:02:03Z","2026-10-11T01:02:03.000+00:00"),
            ("2026-10-11T01:02:03.1Z","2026-10-11T01:02:03.100+00:00"),
            ("2026-10-11T01:02:03.12+05:30","2026-10-11T01:02:03.120+05:30"),
            ("2026-10-11T01:02:03.123-04:00","2026-10-11T01:02:03.123-04:00"),
            ("2026-10-11T01:02:03.1234Z","2026-10-11T01:02:03.123+00:00"),
            ("2026-10-11T01:02:03.9999Z","2026-10-11T01:02:04.000+00:00"),
            ("2026-10-11T01:02:03.0005Z","2026-10-11T01:02:03.001+00:00"),
            ("2026-10-11t01:02:03z","2026-10-11T01:02:03.000+00:00"),
            ("2026-10-11 01:02:03+00:00","2026-10-11T01:02:03.000+00:00"),
            ("2026-10-11T01:02:03-00:00","2026-10-11T01:02:03.000+00:00"),
            ("2026-10-11T24:00:00Z","2026-10-12T00:00:00.000+00:00"),
            ("2024-02-29T00:00:00Z","2024-02-29T00:00:00.000+00:00"),
            ("9999-12-31T23:59:59.999+14:00","9999-12-31T23:59:59.999+14:00"),
            ("2026-10-11T01:02:03+0530","2026-10-11T01:02:03.000+05:30"),
            ("2026-10-11T01:02:03+05","2026-10-11T01:02:03.000+05:00"),
            ("2026-10-11T01:02:03+14:01","2026-10-11T01:02:03.000+14:01"),
            ("2026-10-11T01:02:03+16:00","2026-10-11T01:02:03.000+16:00"),
            ("2026-10-11T01:02:03-16:00","2026-10-11T01:02:03.000-16:00"),
            ("2026-10-11T23:59:59.9999Z","2026-10-12T00:00:00.000+00:00")]
        for (input,expected) in vectors { XCTAssertEqual(try ReferenceDateMetadata.normalize(input),expected,input) }
    }
    func testDeterministicInstalledQtOracleMatrix() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("evidence/mental-command-reference/date-conversion-continuation-20261011/oracle-matrix.tsv")
        let lines = try String(contentsOf: file,encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count,160)
        for line in lines {
            let columns = line.split(separator: "\t",omittingEmptySubsequences: false)
            XCTAssertGreaterThanOrEqual(columns.count,2)
            let expected = columns[1] == "INVALID" ? "" : String(columns[1])
            XCTAssertEqual(try ReferenceDateMetadata.normalize(String(columns[0])),expected,String(columns[0]))
        }
    }
    func testKnownInvalidValuesAndUnsupportedFormsAreDifferent() throws {
        for input in ["2026-10-11T23:59:60Z","2023-02-29T00:00:00Z","0000-01-01T00:00:00Z",
                      "2026-10-11T01:02:03+23:59","2026-10-11T01:02:03+24:00","2026-10-11T01:02:03+16:01",
                      "9999-12-31T24:00:00Z","2026-10-11T24:00:00.001Z"] {
            XCTAssertEqual(try ReferenceDateMetadata.normalize(input),"",input)
        }
        for input in ["bad","2026-10-11","2026-10-11T01:02:03","2026-10-11T01Z"] {
            XCTAssertThrowsError(try ReferenceDateMetadata.normalize(input)) { XCTAssertEqual($0 as? ReferenceDateMetadata.Failure,.unsupportedSyntax) }
        }
        XCTAssertThrowsError(try ReferenceDateMetadata.normalize(String(repeating: "x",count: 65)))
    }
}
