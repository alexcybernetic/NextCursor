import AppKit
import Darwin

private typealias CGSConnectionID = Int32
private typealias CGSMainConnectionIDFunction = @convention(c) () -> CGSConnectionID
private typealias CGSCursorSuppressionFunction = @convention(c) (CGSConnectionID) -> Int32
private typealias CGCursorIsVisibleFunction = @convention(c) () -> Int32

/// Whether WindowServer is currently compositing the native cursor.
///
/// This is a global observation and it cannot attribute a cause. `hidden`
/// means only that nothing is being drawn: it covers this process's
/// suppression, another process's suppression, and the transient obscuring
/// macOS applies while the user types. It is therefore usable for diagnostics
/// and for the standalone check, and unusable as a per-frame control signal.
enum NativeCursorVisibility: String, Equatable {
    case visible
    case hidden
    case unknown
}

/// Balances one native-cursor suppression request against its release.
struct CursorSuppressionLease {
    private(set) var isAcquired = false

    @discardableResult
    mutating func acquire(using suppress: () -> Void) -> Bool {
        guard !isAcquired else { return false }

        suppress()
        isAcquired = true
        return true
    }

    @discardableResult
    mutating func release(using restore: () -> Void) -> Bool {
        guard isAcquired else { return false }

        restore()
        isAcquired = false
        return true
    }
}

enum CursorMaintenanceAction: Equatable {
    case none
    case reapplyFallbackImage
    case reassertSuppressionAndReapplyFallbackImage
}

/// Decides what a maintenance frame must do.
///
/// Holding suppression once is not enough. Other processes share the cursor
/// and can defeat it, and without a recovery path a single defeat persists for
/// the rest of the session: the native cursor then sits on top of NextCursor's
/// own pointer indefinitely rather than flickering.
///
/// An observed `visible` is a sound trigger for recovery whatever its cause,
/// because it means WindowServer is compositing the cursor right now. The
/// converse is not diagnostic — `hidden` covers this process's suppression,
/// another process's, and typing-obscuring alike — but no action is required
/// in that case anyway, so the ambiguity costs nothing.
enum CursorMaintenancePolicy {
    static func action(
        suppressionIsAuthoritative: Bool,
        visibility: NativeCursorVisibility
    ) -> CursorMaintenanceAction {
        // Without an authoritative backend the transparent image is the only
        // defence, and it must be reasserted every frame: comparing cursor
        // seeds can only react after a foreign image has already been drawn,
        // and it latches permanently if this process loses the race to set the
        // cursor, because the foreign seed is then recorded as its own.
        guard suppressionIsAuthoritative else { return .reapplyFallbackImage }

        return visibility == .visible
            ? .reassertSuppressionAndReapplyFallbackImage
            : .none
    }
}

/// How the native cursor is kept off screen.
///
/// `NSCursor.hide()` is scoped to the calling application's active state, and
/// NextCursor is an `.accessory` process that is never frontmost, so AppKit
/// hiding cannot be relied on here. The WindowServer connection-scoped request
/// is not gated on activation, and WindowServer releases it when the
/// connection dies, so an abnormal exit cannot strand the user without a
/// cursor.
struct NativeCursorSuppressor {
    let identifier: String

    /// Whether this backend keeps the cursor off screen on its own. When
    /// false, the caller must maintain the transparent image every frame.
    let isAuthoritative: Bool

    let suppress: () -> Void
    let restore: () -> Void
    let nativeCursorVisibility: () -> NativeCursorVisibility

    private static let coreGraphicsPath =
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"

    static func resolve() -> NativeCursorSuppressor {
        windowServer() ?? appKit()
    }

    private static func windowServer() -> NativeCursorSuppressor? {
        guard let framework = dlopen(coreGraphicsPath, RTLD_LAZY),
            let mainConnectionSymbol = dlsym(framework, "CGSMainConnectionID"),
            let suppressSymbol = dlsym(framework, "CGSHideCursor"),
            let restoreSymbol = dlsym(framework, "CGSShowCursor")
        else {
            return nil
        }

        let mainConnectionID = unsafeBitCast(
            mainConnectionSymbol,
            to: CGSMainConnectionIDFunction.self
        )
        let suppressCursor = unsafeBitCast(
            suppressSymbol,
            to: CGSCursorSuppressionFunction.self
        )
        let restoreCursor = unsafeBitCast(
            restoreSymbol,
            to: CGSCursorSuppressionFunction.self
        )

        let connectionID = mainConnectionID()
        guard connectionID != 0 else { return nil }

        return NativeCursorSuppressor(
            identifier: "windowserver",
            isAuthoritative: true,
            suppress: { _ = suppressCursor(connectionID) },
            restore: { _ = restoreCursor(connectionID) },
            nativeCursorVisibility: visibilityQuery(from: framework)
        )
    }

    private static func appKit() -> NativeCursorSuppressor {
        let framework = dlopen(coreGraphicsPath, RTLD_LAZY)
        return NativeCursorSuppressor(
            identifier: "appkit",
            isAuthoritative: false,
            suppress: NSCursor.hide,
            restore: NSCursor.unhide,
            nativeCursorVisibility: framework.map(visibilityQuery(from:)) ?? { .unknown }
        )
    }

    /// `CGCursorIsVisible` is resolved dynamically rather than called directly
    /// because the declared API is deprecated.
    private static func visibilityQuery(
        from framework: UnsafeMutableRawPointer
    ) -> () -> NativeCursorVisibility {
        guard let symbol = dlsym(framework, "CGCursorIsVisible") else {
            return { .unknown }
        }
        let isVisible = unsafeBitCast(symbol, to: CGCursorIsVisibleFunction.self)
        return { isVisible() != 0 ? .visible : .hidden }
    }
}
