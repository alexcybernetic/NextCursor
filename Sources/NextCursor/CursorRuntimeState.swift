struct CursorRuntimeState {
    var wantsCursor = true
    var userSessionIsActive = true
    var screensAreAwake = true

    func shouldRun(hasAccessibilityPermission: Bool) -> Bool {
        wantsCursor
            && userSessionIsActive
            && screensAreAwake
            && hasAccessibilityPermission
    }
}
