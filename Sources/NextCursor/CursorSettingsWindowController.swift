import AppKit
import SwiftUI

/// Hosts the settings form in a plain window.
///
/// NextCursor runs as an `.accessory` process, so it has to activate itself
/// explicitly for the window to come forward and accept input.
// Main-thread only by construction: driven by AppKit menu actions and a
// SwiftUI form, both of which run on the main thread.
final class CursorSettingsWindowController {
    private let store: CursorSettingsStore
    private var window: NSWindow?

    init(store: CursorSettingsStore) {
        self.store = store
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: CursorSettingsView(store: store)
            )
            hosting.sizingOptions = [.minSize]

            let window = NSWindow(contentViewController: hosting)
            window.title = "NextCursor Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 400, height: 560))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

}
