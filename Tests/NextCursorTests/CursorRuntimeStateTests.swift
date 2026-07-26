import XCTest

@testable import NextCursor

final class CursorRuntimeStateTests: XCTestCase {
    func testAllConditionsMustAllowCursorToRun() {
        let state = CursorRuntimeState()

        XCTAssertTrue(state.shouldRun(hasAccessibilityPermission: true))
        XCTAssertFalse(state.shouldRun(hasAccessibilityPermission: false))
    }

    func testScreenWakeDoesNotReactivateInactiveUserSession() {
        var state = CursorRuntimeState()

        state.userSessionIsActive = false
        state.screensAreAwake = false
        state.screensAreAwake = true

        XCTAssertFalse(state.shouldRun(hasAccessibilityPermission: true))
    }

    func testSessionActivationDoesNotRunWhileScreensSleep() {
        var state = CursorRuntimeState()

        state.screensAreAwake = false
        state.userSessionIsActive = false
        state.userSessionIsActive = true

        XCTAssertFalse(state.shouldRun(hasAccessibilityPermission: true))
    }

    func testUserPreferenceDisablesCursor() {
        var state = CursorRuntimeState()
        state.wantsCursor = false

        XCTAssertFalse(state.shouldRun(hasAccessibilityPermission: true))
    }
}
