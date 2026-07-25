import AppKit
import CoreGraphics
import Darwin
import JavaRuntimeSupport

private typealias CursorSeedQuery = @convention(c) () -> UInt32

/// Keeps the native cursor invisible while NextCursor is active and balances
/// every hide operation before the process exits.
final class SystemCursorController {
    private let transparentCursor = SystemCursorController.makeTransparentCursor()
    private let cursorSeedQuery = SystemCursorController.loadCursorSeedQuery()
    private var lastCursorSeed: UInt32?
    private var lastSystemCursor: NSCursor?
    private var successfulHideCalls = 0
    private var wantsHidden = false

    func hide() {
        guard !wantsHidden else { return }

        // NextCursor is an LSUIElement menu-bar process. This Apple-framework
        // opt-in permits cursor changes from a background application.
        NSCursor.javaSetAllowsCursorSet(inBackground: true)
        wantsHidden = true
        applyHide()
    }

    /// Dock hover, clicks, app changes, and display transitions can replace or
    /// reveal the native cursor. Cursor seed changes identify those real state
    /// transitions without relying on the deprecated visibility API.
    func maintainHiddenState(force: Bool = false) {
        guard wantsHidden else { return }

        let currentSeed = cursorSeedQuery?()
        let currentSystemCursor = NSCursor.currentSystem
        let seedChanged = currentSeed != nil && currentSeed != lastCursorSeed
        let cursorChanged = currentSeed == nil
            && currentSystemCursor != nil
            && currentSystemCursor !== lastSystemCursor

        guard force || seedChanged || cursorChanged else { return }
        applyHide()
    }

    func show() {
        guard wantsHidden else { return }

        // Core Graphics cursor hiding is reference counted. Balance every
        // successful call exactly, including reassertions after Dock resets.
        for _ in 0..<successfulHideCalls {
            _ = CGDisplayShowCursor(CGMainDisplayID())
        }

        NSCursor.arrow.set()
        NSCursor.javaSetAllowsCursorSet(inBackground: false)

        successfulHideCalls = 0
        wantsHidden = false
        lastCursorSeed = nil
        lastSystemCursor = nil
    }

    private func applyHide() {
        if CGDisplayHideCursor(CGMainDisplayID()) == .success {
            successfulHideCalls += 1
        }
        transparentCursor.set()

        // Both operations above may advance the seed/current cursor. Capture
        // the resulting state so the next frame does not re-hide needlessly.
        lastCursorSeed = cursorSeedQuery?()
        lastSystemCursor = NSCursor.currentSystem
    }

    private static func loadCursorSeedQuery() -> CursorSeedQuery? {
        let frameworkPath = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
        guard let coreGraphics = dlopen(frameworkPath, RTLD_LAZY),
              let symbol = dlsym(coreGraphics, "CGSCurrentCursorSeed") else {
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
