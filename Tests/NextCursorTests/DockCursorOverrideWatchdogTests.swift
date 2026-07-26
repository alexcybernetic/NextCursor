import XCTest

@testable import NextCursor

final class DockCursorOverrideWatchdogTests: XCTestCase {
    func testOrdinaryLaunchDoesNotEnterWatchdogMode() {
        XCTAssertFalse(
            DockCursorOverrideWatchdog.runIfRequested(arguments: ["NextCursor"])
        )
    }

    func testUnrelatedArgumentDoesNotEnterWatchdogMode() {
        XCTAssertFalse(
            DockCursorOverrideWatchdog.runIfRequested(
                arguments: ["NextCursor", "--unrelated"]
            )
        )
    }
}
