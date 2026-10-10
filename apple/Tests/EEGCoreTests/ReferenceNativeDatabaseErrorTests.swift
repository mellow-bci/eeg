import XCTest
@testable import EEGCore

final class ReferenceNativeDatabaseErrorTests: XCTestCase {
    func testCapturedNumericDomainJumpTableAndCodeBoundaries() {
        for code in [Int32(1),32,33,Int32.max] {
            XCTAssertEqual(ReferenceNativeDatabaseError.map(domain: 1,code: code),code < 33 ? code : 65535)
            for (domain,expected) in [(Int32(2),Int32(35)),(3,33),(4,34),(5,65535),(6,65535),(7,36)] {
                XCTAssertEqual(ReferenceNativeDatabaseError.map(domain: domain,code: code),expected)
            }
        }
        for domain in [Int32.min,-1,0,1,7,8,Int32.max] {
            XCTAssertEqual(ReferenceNativeDatabaseError.map(domain: domain,code: 0),0)
            XCTAssertEqual(ReferenceNativeDatabaseError.map(domain: domain,code: -1),0)
        }
        for domain in [Int32.min,-1,0,8,Int32.max] {
            XCTAssertEqual(ReferenceNativeDatabaseError.map(domain: domain,code: 1),65535)
        }
    }
}
