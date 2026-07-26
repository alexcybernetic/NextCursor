import AppKit
import Darwin
import JavaRuntimeSupport

private typealias CursorSeedQuery = @convention(c) () -> UInt32

/// Keeps the native cursor off screen while NextCursor is active and balances
/// every suppression request before the process exits.
final class SystemCursorController {
    private let diagnostics = CursorDiagnostics.shared
    private let transparentCursor = SystemCursorController.makeTransparentCursor()
    private let cursorSeedQuery = SystemCursorController.loadCursorSeedQuery()
    private let suppressor = NativeCursorSuppressor.resolve()
    private let dockCursorOverrideWatchdog = DockCursorOverrideWatchdog()
    private let usesDockCursorOverrideExperiment =
        ProcessInfo.processInfo.environment["NEXTCURSOR_DOCK_OVERRIDE_EXPERIMENT"] == "1"
    private var lease = CursorSuppressionLease()
    private var wantsHidden = false

    func hide() {
        guard !wantsHidden else { return }

        // NextCursor is an LSUIElement menu-bar process. This Apple-framework
        // opt-in permits cursor changes from a background application.
        NSCursor.javaSetAllowsCursorSet(inBackground: true)
        wantsHidden = true
        if usesDockCursorOverrideExperiment, dockCursorOverrideWatchdog.start() {
            diagnostics.recordCursorOperation("block-dock-override", reason: "start")
        }
        acquireSuppression(reason: "start")
        applyTransparentCursor()
        recordCursorState(context: "start")
    }

    /// Recovers suppression when something has defeated it, and maintains the
    /// transparent-image fallback when suppression cannot hold on its own.
    func maintainHiddenState() {
        guard wantsHidden else { return }

        switch CursorMaintenancePolicy.action(
            suppressionIsAuthoritative: suppressor.isAuthoritative,
            visibility: suppressor.nativeCursorVisibility()
        ) {
        case .none:
            return
        case .reassertSuppressionAndReapplyFallbackImage:
            reassertSuppression()
            applyTransparentCursor()
            recordCursorState(context: "after-reassert")
        case .reapplyFallbackImage:
            applyTransparentCursor()
            recordCursorState(context: "after-reapply")
        }
    }

    func show() {
        if usesDockCursorOverrideExperiment, dockCursorOverrideWatchdog.stop() {
            diagnostics.recordCursorOperation("allow-dock-override", reason: "stop")
        }

        if lease.release(using: suppressor.restore) {
            diagnostics.recordCursorOperation(
                "restore",
                reason: "stop via \(suppressor.identifier)"
            )
        }

        guard wantsHidden else { return }

        NSCursor.arrow.set()
        NSCursor.javaSetAllowsCursorSet(inBackground: false)

        wantsHidden = false
        recordCursorState(context: "stop")
    }

    /// Re-arms suppression rather than stacking a second request. The
    /// outstanding count stays at one however often this fires, so shutdown
    /// stays exactly balanced. Stacking instead drove a feedback loop: each
    /// extra request made the next reading more likely to disagree, and the
    /// escalation ceiling left the cursor suppressed with nothing to release it.
    private func reassertSuppression() {
        lease.release(using: suppressor.restore)
        if lease.acquire(using: suppressor.suppress) {
            diagnostics.recordCursorOperation(
                "re-arm",
                reason: "native cursor composited while suppressed"
            )
        }
    }

    private func acquireSuppression(reason: String) {
        if lease.acquire(using: suppressor.suppress) {
            diagnostics.recordCursorOperation(
                "suppress",
                reason: "\(reason) via \(suppressor.identifier)"
            )
        }
    }

    private func applyTransparentCursor() {
        transparentCursor.set()
    }

    private func recordCursorState(context: String) {
        guard diagnostics.isEnabled else { return }
        diagnostics.observeCursor(
            seed: cursorSeedQuery?(),
            visibility: suppressor.nativeCursorVisibility(),
            wantsHidden: wantsHidden,
            hasSuppressionLease: lease.isAcquired,
            suppressor: suppressor.identifier,
            context: context
        )
    }

    private static func loadCursorSeedQuery() -> CursorSeedQuery? {
        let frameworkPath = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
        guard let coreGraphics = dlopen(frameworkPath, RTLD_LAZY),
            let symbol = dlsym(coreGraphics, "CGSCurrentCursorSeed")
        else {
            return nil
        }
        return unsafeBitCast(symbol, to: CursorSeedQuery.self)
    }

    private static func makeTransparentCursor() -> NSCursor {
        let width = 16
        let height = 16
        let bytesPerRow = width * 4
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: bytesPerRow,
            bitsPerPixel: 32
        )!
        representation.bitmapData?.initialize(repeating: 0, count: bytesPerRow * height)

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(representation)
        return NSCursor(image: image, hotSpot: .zero)
    }

    deinit {
        show()
    }
}
