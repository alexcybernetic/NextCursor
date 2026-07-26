import AppKit
import Darwin

if CursorInventoryCommand.isRequested() {
    // The private named-copy query requires an established Aqua session
    // connection. Creating NSApplication establishes it without entering the
    // run loop or starting NextCursor's cursor engine.
    _ = NSApplication.shared
    exit(CursorInventoryCommand.run())
}

if DockCursorOverrideWatchdog.runIfRequested() {
    exit(EXIT_SUCCESS)
}

if CursorSuppressionCheckCommand.isRequested() {
    // Cursor suppression and NSCursor both require an established Aqua session
    // connection. Creating NSApplication establishes it without entering the
    // run loop or starting NextCursor's cursor engine.
    _ = NSApplication.shared
    exit(CursorSuppressionCheckCommand.run())
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
