import XCTest
@testable import EEGCore

final class RecordingClockAnchorTests: XCTestCase {
    func testStoredAnchorRoundTripPreservesMappingAndUTCOffset() throws {
        let original = try EEGRecordingClockAnchor(receiptBefore: 10.125, receiptAfter: 10.375,
            wallUnixSeconds: 1770000000.25, localUTCOffsetSeconds: 19800)
        let data = try JSONEncoder().encode(original)
        let recovered = try JSONDecoder().decode(EEGRecordingClockAnchor.self, from: data)
        XCTAssertEqual(recovered.localUTCOffsetSeconds, 19800)
        XCTAssertEqual(recovered.receiptBefore, original.receiptBefore)
        XCTAssertEqual(recovered.receiptAfter, original.receiptAfter)
        XCTAssertEqual(recovered.wallUnixSeconds, original.wallUnixSeconds)
        for receipt in [0.0, 10.2, 100.0] {
            XCTAssertEqual(try recovered.wallTimeBounds(forReceiptSeconds: receipt),
                           try original.wallTimeBounds(forReceiptSeconds: receipt))
        }
    }
    func testStoredAnchorCannotBypassNumericOrProvenanceValidation() throws {
        let anchor = try EEGRecordingClockAnchor(receiptBefore: 1, receiptAfter: 2,
            wallUnixSeconds: 1000, localUTCOffsetSeconds: 0)
        let original = try JSONSerialization.jsonObject(with: JSONEncoder().encode(anchor)) as! [String: Any]
        let mutations: [(String, Any)] = [("schema", "eeg.recording-clock-anchor.v2"),
            ("timeBasis", "device_seconds"), ("wallClockAccuracy", "verified"),
            ("receiptBefore", -1), ("receiptAfter", 0), ("receiptBefore", true),
            ("localUTCOffsetSeconds", 86401), ("localUTCOffsetSeconds", 1.25),
            ("wallUnixSeconds", "1000"), ("receiptAfter", NSNull())]
        for (key, value) in mutations {
            var object = original; object[key] = value
            XCTAssertThrowsError(try JSONDecoder().decode(EEGRecordingClockAnchor.self,
                from: JSONSerialization.data(withJSONObject: object)), key)
        }
        for key in original.keys {
            var object = original; object.removeValue(forKey: key)
            XCTAssertThrowsError(try JSONDecoder().decode(EEGRecordingClockAnchor.self,
                from: JSONSerialization.data(withJSONObject: object)), key)
        }
    }
    func testBracketUsesReceiptClockAndRetainsUncertainty() throws {
        var calls = [String](), receipts = [10.0, 10.25]
        let anchor = try EEGRecordingClockAnchor.capture(receiptClock: {
            calls.append("receipt"); return receipts.removeFirst()
        }, wallClock: {
            calls.append("wall"); return Date(timeIntervalSince1970: 1000.125)
        }, timeZone: TimeZone(secondsFromGMT: 19800)!)
        XCTAssertEqual(calls,["receipt","wall","receipt"])
        XCTAssertEqual(anchor.receiptBefore,10)
        XCTAssertEqual(anchor.receiptAfter,10.25)
        XCTAssertEqual(anchor.localUTCOffsetSeconds,19800)
        XCTAssertEqual(try anchor.wallTimeBounds(forReceiptSeconds:11),1000.875...1001.125)
        XCTAssertEqual(try anchor.wallTimeBounds(forReceiptSeconds:9),998.875...999.125)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(anchor)) as? [String:Any])
        XCTAssertEqual(json["schema"] as? String,"eeg.recording-clock-anchor.v1")
        XCTAssertEqual(json["wallClockAccuracy"] as? String,"unmeasured")
        XCTAssertEqual(json["wallUnixSeconds"] as? Double,1000.125)
    }
    func testRejectsInvalidBoundsAndNonfiniteMapping() throws {
        for (before,after,wall) in [(1.0,0.0,100.0),(-1,0,100),(0,Double.infinity,100),(0,1,Double.nan)] {
            XCTAssertThrowsError(try EEGRecordingClockAnchor(receiptBefore:before,receiptAfter:after,wallUnixSeconds:wall,localUTCOffsetSeconds:0))
        }
        let anchor = try EEGRecordingClockAnchor(receiptBefore:0,receiptAfter:0,wallUnixSeconds:Double.greatestFiniteMagnitude,localUTCOffsetSeconds:0)
        XCTAssertThrowsError(try anchor.wallTimeBounds(forReceiptSeconds:.greatestFiniteMagnitude))
        XCTAssertThrowsError(try anchor.wallTimeBounds(forReceiptSeconds:.nan))
        XCTAssertThrowsError(try anchor.wallTimeBounds(forReceiptSeconds:-1))
    }
}
