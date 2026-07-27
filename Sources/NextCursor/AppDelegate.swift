import AppKit
import ApplicationServices
import Combine
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let engine = CursorEngine()
    private var runtimeState = CursorRuntimeState()
    private var statusItem: NSStatusItem!
    private var enableItem: NSMenuItem!
    private var inertiaItem: NSMenuItem!
    private var permissionItem: NSMenuItem!
    private var permissionTimer: Timer?
    private var emergencyHotKey: EmergencyHotKey?
    private var emergencyHotKeyError: EmergencyHotKey.RegistrationError?
    private var terminationSignalSources: [DispatchSourceSignal] = []
    private var isReadyToReconcile = false
    private let settingsStore = CursorSettingsStore()
    private lazy var settingsWindowController = CursorSettingsWindowController(
        store: settingsStore
    )
    private var settingsSubscription: AnyCancellable?

    func applicationWillFinishLaunching(_ notification: Notification) {
        observeRuntimeState()
        runtimeState.screensAreAwake = CGDisplayIsAsleep(CGMainDisplayID()) == 0
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Running the app means the adaptive cursor is enabled. Whether it is
        // enabled is tied to the process; how it looks is persisted.
        runtimeState.wantsCursor = true
        engine.applySettings(settingsStore.settings)

        do {
            emergencyHotKey = try EmergencyHotKey { [weak self] in
                self?.toggleEnabled()
            }
        } catch let error as EmergencyHotKey.RegistrationError {
            emergencyHotKeyError = error
            NSLog("NextCursor emergency hotkey unavailable: %@", error.localizedDescription)
        } catch {
            NSLog("NextCursor emergency hotkey unavailable: %@", error.localizedDescription)
        }

        setUpStatusItem()

        // Subscribed only after the status item exists: a @Published publisher
        // delivers its current value synchronously on subscription, so an
        // earlier sink would drive the menu before it was built.
        settingsSubscription = settingsStore.$settings.sink { [weak self] settings in
            self?.engine.applySettings(settings)
            self?.updateMenu()
        }

        installTerminationHandlers()
        startPermissionTimer()
        isReadyToReconcile = true
        reconcileState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        settingsSubscription?.cancel()
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
            button.image = CometMark.statusItemImage(isActive: false)
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

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        permissionItem = NSMenuItem(
            title: "Accessibility Permission…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        permissionItem.target = self
        menu.addItem(permissionItem)

        let emergencyItem = NSMenuItem(
            title: emergencyHotKey == nil
                ? "Emergency Toggle Unavailable"
                : "Emergency Toggle: ⌃⌥⌘P",
            action: nil,
            keyEquivalent: ""
        )
        emergencyItem.isEnabled = false
        emergencyItem.toolTip = emergencyHotKeyError?.localizedDescription
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
        guard statusItem != nil else { return }

        let trusted = AXIsProcessTrusted()
        if !trusted {
            enableItem.state = .off
            enableItem.title = "Cursor Inactive — Accessibility Required"
            enableItem.isEnabled = false
        } else {
            enableItem.state = runtimeState.wantsCursor ? .on : .off
            enableItem.title = runtimeState.wantsCursor ? "NextCursor Enabled" : "Enable NextCursor"
            enableItem.isEnabled = true
        }
        inertiaItem.state = settingsStore.settings.usesPointerInertia ? .on : .off
        permissionItem.title = trusted
            ? "Accessibility: Granted"
            : "Open Accessibility Settings…"
        permissionItem.isEnabled = !trusted

        statusItem.button?.image = CometMark.statusItemImage(isActive: engine.isRunning)
    }

    private func observeRuntimeState() {
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
            selector: #selector(screensSlept),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(screensWoke),
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
        guard isReadyToReconcile else { return }

        let shouldRun = runtimeState.shouldRun(
            hasAccessibilityPermission: AXIsProcessTrusted()
        )
        if shouldRun {
            engine.start()
        } else {
            engine.stop()
        }
        updateMenu()
    }

    @objc private func toggleEnabled() {
        guard AXIsProcessTrusted() else { return }

        runtimeState.wantsCursor.toggle()
        reconcileState()
    }

    @objc private func togglePointerInertia() {
        settingsStore.set(
            !settingsStore.settings.usesPointerInertia,
            for: \.usesPointerInertia
        )
    }

    @objc private func showSettings() {
        settingsWindowController.show()
    }

    @objc private func openAccessibilitySettings() {
        guard !AXIsProcessTrusted(),
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func showAbout() {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let credits = NSMutableAttributedString(
            string: "Adaptive mouse cursor for the next generation.\n\n",
            attributes: [.paragraphStyle: paragraphStyle]
        )
        credits.append(
            NSAttributedString(
                string: "github.com/alexcybernetic/NextCursor",
                attributes: [
                    .foregroundColor: NSColor.linkColor,
                    .link: URL(string: "https://github.com/alexcybernetic/NextCursor")!,
                    .paragraphStyle: paragraphStyle
                ]
            )
        )

        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "NextCursor",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development",
            .credits: credits
        ]
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    @objc private func quit() {
        engine.stop()
        NSApp.terminate(nil)
    }

    @objc private func sessionResigned() {
        runtimeState.userSessionIsActive = false
        reconcileState()
    }

    @objc private func sessionBecameActive() {
        runtimeState.userSessionIsActive = true
        reconcileState()
    }

    @objc private func screensSlept() {
        runtimeState.screensAreAwake = false
        reconcileState()
    }

    @objc private func screensWoke() {
        runtimeState.screensAreAwake = true
        reconcileState()
    }
}
