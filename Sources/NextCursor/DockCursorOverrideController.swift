import Darwin

private typealias CGSConnectionID = Int32
private typealias CGSMainConnectionIDFunction = @convention(c) () -> CGSConnectionID
private typealias CGSSetDockCursorOverrideFunction = @convention(c) (CGSConnectionID, Bool) -> Void

struct DockCursorOverrideLease {
    private(set) var isAcquired = false

    @discardableResult
    mutating func acquire(using setAllowsDockOverride: (Bool) -> Void) -> Bool {
        guard !isAcquired else { return false }

        setAllowsDockOverride(false)
        isAcquired = true
        return true
    }

    @discardableResult
    mutating func release(using setAllowsDockOverride: (Bool) -> Void) -> Bool {
        guard isAcquired else { return false }

        setAllowsDockOverride(true)
        isAcquired = false
        return true
    }
}

/// Prevents Dock from replacing the cursor while NextCursor is active. The SPI
/// is resolved dynamically; a separate watchdog restores the session-wide flag
/// if the app exits before its normal cleanup runs.
struct DockCursorOverrideController {
    private let connectionID: CGSConnectionID
    private let setDockCursorOverride: CGSSetDockCursorOverrideFunction
    private var lease = DockCursorOverrideLease()

    init?() {
        guard let process = dlopen(nil, RTLD_LAZY),
            let mainConnectionSymbol = dlsym(process, "CGSMainConnectionID"),
            let setOverrideSymbol = dlsym(process, "CGSSetDockCursorOverride")
        else {
            return nil
        }

        let mainConnectionID = unsafeBitCast(
            mainConnectionSymbol,
            to: CGSMainConnectionIDFunction.self
        )
        setDockCursorOverride = unsafeBitCast(
            setOverrideSymbol,
            to: CGSSetDockCursorOverrideFunction.self
        )

        let connectionID = mainConnectionID()
        guard connectionID != 0 else { return nil }
        self.connectionID = connectionID
    }

    @discardableResult
    mutating func acquire() -> Bool {
        let setDockCursorOverride = setDockCursorOverride
        return lease.acquire { allowsOverride in
            setDockCursorOverride(connectionID, allowsOverride)
        }
    }

    @discardableResult
    mutating func release() -> Bool {
        let setDockCursorOverride = setDockCursorOverride
        return lease.release { allowsOverride in
            setDockCursorOverride(connectionID, allowsOverride)
        }
    }
}
