import AppKit
import ApplicationServices
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let engine = CursorEngine()
    private var statusItem: NSStatusItem!
    private var enableItem: NSMenuItem!
    private var inertiaItem: NSMenuItem!
    private var permissionItem: NSMenuItem!
    private var permissionTimer: Timer?
    private var emergencyHotKey: EmergencyHotKey?
    private var terminationSignalSources: [DispatchSourceSignal] = []
    private var sessionIsActive = true
    private var wantsCursor = true
    private var usesPointerInertia = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Running the app means the adaptive cursor is enabled. Nothing about
        // that state is persisted after the process exits.
        wantsCursor = true
        usesPointerInertia = true
        engine.setPointerInertiaEnabled(true)

        setUpStatusItem()
        observeSessionState()
        installTerminationHandlers()
        emergencyHotKey = EmergencyHotKey { [weak self] in
            self?.toggleEnabled()
        }
        startPermissionTimer()
        reconcileState()

        if !AXIsProcessTrusted() {
            DispatchQueue.main.async { [weak self] in
                self?.explainAccessibilityPermission()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        engine.stop()
        terminationSignalSources.forEach { $0.cancel() }
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateMenu()
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "circle.dashed", accessibilityDescription: "NextCursor")
            button.image?.isTemplate = true
            button.toolTip = "NextCursor"
        }

        let menu = NSMenu()
        menu.delegate = self

        enableItem = NSMenuItem(
            title: "Enable NextCursor",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        enableItem.target = self
        menu.addItem(enableItem)

        inertiaItem = NSMenuItem(
            title: "Pointer Inertia",
            action: #selector(togglePointerInertia),
            keyEquivalent: ""
        )
        inertiaItem.target = self
        menu.addItem(inertiaItem)

        permissionItem = NSMenuItem(
            title: "Accessibility Permission…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        permissionItem.target = self
        menu.addItem(permissionItem)

        let revealItem = NSMenuItem(
            title: "Reveal This App in Finder",
            action: #selector(revealAppInFinder),
            keyEquivalent: ""
        )
        revealItem.target = self
        menu.addItem(revealItem)

        let emergencyItem = NSMenuItem(
            title: "Emergency Toggle: ⌃⌥⌘P",
            action: nil,
            keyEquivalent: ""
        )
        emergencyItem.isEnabled = false
        menu.addItem(emergencyItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(
            title: "About NextCursor",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(
            title: "Restore System Cursor and Quit",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateMenu()
    }

    private func updateMenu() {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            enableItem.state = .off
            enableItem.title = "Cursor Inactive — Accessibility Required…"
        } else {
            enableItem.state = wantsCursor ? .on : .off
            enableItem.title = wantsCursor ? "NextCursor Enabled" : "Enable NextCursor"
        }
        inertiaItem.state = usesPointerInertia ? .on : .off
        permissionItem.title = trusted
            ? "Accessibility: Granted"
            : "Accessibility Required for This App Copy…"

        if let image = NSImage(
            systemSymbolName: engine.isRunning ? "circle.fill" : "circle.dashed",
            accessibilityDescription: "NextCursor"
        ) {
            image.isTemplate = true
            statusItem.button?.image = image
        }
    }

    private func observeSessionState() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(sessionResigned),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(sessionBecameActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(sessionResigned),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(sessionBecameActive),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }

    private func installTerminationHandlers() {
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            Darwin.signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in
                self?.engine.stop()
                NSApp.terminate(nil)
            }
            source.resume()
            terminationSignalSources.append(source)
        }
    }

    private func startPermissionTimer() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.reconcileState()
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    private func reconcileState() {
        let shouldRun = wantsCursor && sessionIsActive && AXIsProcessTrusted()
        if shouldRun {
            engine.start()
        } else {
            engine.stop()
        }
        updateMenu()
    }

    private func explainAccessibilityPermission() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "This Copy Needs Accessibility Access"
        alert.informativeText = "macOS grants Accessibility access to a specific signed app copy. An entry for an older NextCursor does not authorize this portable copy.\n\nRemove the old entry if necessary, then add this exact app:\n\n\(Bundle.main.bundlePath)\n\nNextCursor reads structural metadata only; it does not read labels or values or perform actions."
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "Reveal This App")
        alert.addButton(withTitle: "Not Now")

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            requestAccessibilityPermission()
        case .alertSecondButtonReturn:
            revealAppInFinder()
        default:
            break
        }
    }

    private func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        // The system prompt normally links directly to this pane. Opening it
        // as well makes recovery straightforward if permission was declined.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard !AXIsProcessTrusted(),
                  let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
                return
            }
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleEnabled() {
        guard AXIsProcessTrusted() else {
            explainAccessibilityPermission()
            return
        }

        wantsCursor.toggle()
        reconcileState()
    }

    @objc private func togglePointerInertia() {
        usesPointerInertia.toggle()
        engine.setPointerInertiaEnabled(usesPointerInertia)
        updateMenu()
    }

    @objc private func openAccessibilitySettings() {
        if AXIsProcessTrusted() {
            let alert = NSAlert()
            alert.messageText = "Accessibility Access Is Enabled"
            alert.informativeText = "NextCursor uses it only to read structural metadata for the control directly beneath the pointer."
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        } else {
            explainAccessibilityPermission()
        }
    }

    @objc private func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    @objc private func showAbout() {
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "NextCursor",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development",
            .credits: NSAttributedString(string: "An iPad-style adaptive pointer for macOS.\nEverything runs locally on your Mac.")
        ]
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    @objc private func quit() {
        engine.stop()
        NSApp.terminate(nil)
    }

    @objc private func sessionResigned() {
        sessionIsActive = false
        reconcileState()
    }

    @objc private func sessionBecameActive() {
        sessionIsActive = true
        reconcileState()
    }
}
