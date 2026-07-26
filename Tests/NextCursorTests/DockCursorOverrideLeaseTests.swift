import XCTest

@testable import NextCursor

final class DockCursorOverrideLeaseTests: XCTestCase {
    func testAcquireBlocksDockOverrideOnlyOnce() {
        var values = [Bool]()
        var lease = DockCursorOverrideLease()

        for _ in 0..<5 {
            lease.acquire { values.append($0) }
        }

        XCTAssertTrue(lease.isAcquired)
        XCTAssertEqual(values, [false])
    }

    func testReleaseRestoresDockOverrideOnlyOnce() {
        var values = [Bool]()
        var lease = DockCursorOverrideLease()
        lease.acquire { values.append($0) }

        for _ in 0..<5 {
            lease.release { values.append($0) }
        }

        XCTAssertFalse(lease.isAcquired)
        XCTAssertEqual(values, [false, true])
    }

    func testLeaseCanBeReacquiredAfterRelease() {
        var values = [Bool]()
        var lease = DockCursorOverrideLease()

        lease.acquire { values.append($0) }
        lease.release { values.append($0) }
        lease.acquire { values.append($0) }
        lease.release { values.append($0) }

        XCTAssertFalse(lease.isAcquired)
        XCTAssertEqual(values, [false, true, false, true])
    }
}
