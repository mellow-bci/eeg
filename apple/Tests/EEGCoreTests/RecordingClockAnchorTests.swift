import XCTest
@testable import EEGCore

final class RecordingClockAnchorTests: XCTestCase {
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
