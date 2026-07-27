import AppKit
import CoreGraphics
import QuartzCore

private final class CursorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct CursorDrawingState {
    var controlAmount: CGFloat = 0
    var textAmount: CGFloat = 0
    var pressedAmount: CGFloat = 0
}

private final class CursorView: NSView {
    var drawingState = CursorDrawingState() {
        didSet { needsDisplay = true }
    }

    var pointerSettings = CursorAppearanceSettings() {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let shapeRect = bounds.insetBy(dx: CursorOverlay.padding, dy: CursorOverlay.padding)
        guard shapeRect.width > 0, shapeRect.height > 0 else { return }

        let state = drawingState
        let textAmount = state.textAmount.clamped(to: 0...1)
        let controlAmount = state.controlAmount.clamped(to: 0...1)
        let shapeAlpha = 1 - textAmount
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        if shapeAlpha > 0.001 {
            drawPointer(
                in: shapeRect,
                controlAmount: controlAmount,
                shapeAlpha: shapeAlpha,
                isDark: isDark
            )
        }

        if textAmount > 0.001 {
            drawIBeam(in: shapeRect, alpha: textAmount, isDark: isDark)
        }
    }

    private func drawPointer(
        in shapeRect: NSRect,
        controlAmount: CGFloat,
        shapeAlpha: CGFloat,
        isDark: Bool
    ) {
        let controlFill = pointerSettings.controlFill(isDark: isDark)
        let fill = pointerSettings
            .fill(isDark: isDark)
            .blended(toward: controlFill, amount: Double(controlAmount))

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 5 + (4 * controlAmount)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.20 * shapeAlpha)
        shadow.set()

        let roundedPath = roundedRectanglePath(in: shapeRect)
        let customPath = customPath(in: shapeRect)

        // A polygon or heart cannot morph into the snapped control's rounded
        // rectangle through the corner-radius spring, so the two cross-fade.
        let customAmount = customPath == nil ? 0 : (1 - controlAmount)

        if let customPath, customAmount > 0.001 {
                fill.nsColor
                    .withAlphaComponent(fill.alpha * shapeAlpha * customAmount)
                    .setFill()
            customPath.fill()
        }
        if customAmount < 0.999 {
            fill.nsColor
                .withAlphaComponent(fill.alpha * shapeAlpha * (1 - customAmount))
                .setFill()
            roundedPath.fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        strokeBorder(
            roundedPath: roundedPath,
            customPath: customPath,
            customAmount: customAmount,
            controlAmount: controlAmount,
            shapeAlpha: shapeAlpha,
            isDark: isDark
        )
    }

    private func strokeBorder(
        roundedPath: NSBezierPath,
        customPath: NSBezierPath?,
        customAmount: CGFloat,
        controlAmount: CGFloat,
        shapeAlpha: CGFloat,
        isDark: Bool
    ) {
        let borderWidth = CGFloat(pointerSettings.borderWidth)
        if borderWidth > 0.01 {
            let border = pointerSettings.border(isDark: isDark)
            // The user's border belongs to the free pointer. The snapped state
            // keeps its own hairline, so this fades out as the pointer morphs.
            let freeAmount = 1 - controlAmount
            if freeAmount > 0.001 {
                border.nsColor
                    .withAlphaComponent(border.alpha * shapeAlpha * freeAmount)
                    .setStroke()
                if let customPath, customAmount > 0.001 {
                    customPath.lineWidth = borderWidth
                    customPath.stroke()
                }
                if customAmount < 0.999 {
                    roundedPath.lineWidth = borderWidth
                    roundedPath.stroke()
                }
            }
        }

        let controlBorderWidth = CGFloat(pointerSettings.controlBorderWidth)
        if controlAmount > 0.01, controlBorderWidth > 0.01 {
            let controlBorder = pointerSettings.controlBorder(isDark: isDark)
            controlBorder.nsColor
                .withAlphaComponent(controlBorder.alpha * controlAmount * shapeAlpha)
                .setStroke()
            roundedPath.lineWidth = controlBorderWidth
            roundedPath.stroke()
        }
    }

    private func roundedRectanglePath(in shapeRect: NSRect) -> NSBezierPath {
        let radius = min(
            CursorOverlay.currentCornerRadius,
            min(shapeRect.width, shapeRect.height) / 2
        )
        return NSBezierPath(roundedRect: shapeRect, xRadius: radius, yRadius: radius)
    }

    private func customPath(in shapeRect: NSRect) -> NSBezierPath? {
        pointerSettings.shape.customPath(in: shapeRect)
    }

    private func drawIBeam(in rect: NSRect, alpha: CGFloat, isDark: Bool) {
        let centerX = rect.midX
        let top = rect.maxY - 1
        let bottom = rect.minY + 1
        let capWidth: CGFloat = 8
        let path = NSBezierPath()
        path.move(to: NSPoint(x: centerX, y: bottom))
        path.line(to: NSPoint(x: centerX, y: top))
        path.move(to: NSPoint(x: centerX - capWidth / 2, y: bottom))
        path.line(to: NSPoint(x: centerX + capWidth / 2, y: bottom))
        path.move(to: NSPoint(x: centerX - capWidth / 2, y: top))
        path.line(to: NSPoint(x: centerX + capWidth / 2, y: top))

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 2
        shadow.shadowColor = (isDark ? NSColor.black : NSColor.white).withAlphaComponent(0.65 * alpha)
        shadow.set()

        (isDark ? NSColor.white : NSColor.black).withAlphaComponent(0.88 * alpha).setStroke()
        path.lineWidth = 1.7
        path.lineCapStyle = .round
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class CursorOverlay {
    static let padding: CGFloat = 20

    // CursorView reads this only while drawing on the main thread. Keeping the
    // radius here avoids expanding the drawing-state value type every frame.
    fileprivate static var currentCornerRadius: CGFloat = 10

    private let panel: CursorPanel
    private let cursorView: CursorView

    private var center = CGPoint.zero
    private var centerVelocity = CGVector.zero
    private var size = CGSize(width: 20, height: 20)
    private var sizeVelocity = CGVector.zero
    private var cornerRadius: CGFloat = 10
    private var cornerVelocity: CGFloat = 0
    private var controlAmount: CGFloat = 0
    private var textAmount: CGFloat = 0
    private var pressedAmount: CGFloat = 0
    private var opacity: CGFloat = 1
    private var initialized = false
    private var settings = CursorAppearanceSettings()

    init(initialPosition: CGPoint) {
        center = initialPosition

        let initialFrame = CGRect(x: 0, y: 0, width: 60, height: 60)
        panel = CursorPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        cursorView = CursorView(frame: initialFrame)

        panel.contentView = cursorView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.cursorWindow)) - 1)

        // Treat the adaptive cursor as normal shareable window content so it
        // remains visible in full-display screenshots and screen recordings.
        panel.sharingType = .readOnly

        let initialShapeFrame = CGRect(
            x: initialPosition.x - 10,
            y: initialPosition.y - 10,
            width: 20,
            height: 20
        )
        panel.setFrame(
            Self.appKitRect(fromQuartzRect: initialShapeFrame.insetBy(dx: -Self.padding, dy: -Self.padding)),
            display: false
        )
        panel.orderFrontRegardless()
    }

    func update(
        physicalPosition: CGPoint,
        target: CursorTarget?,
        usesPointerInertia: Bool,
        isPressed: Bool,
        isVisible: Bool,
        deltaTime: CGFloat
    ) {
        // Capping the physics step keeps the spring stable after a stalled
        // run-loop frame (for example while the system is changing Spaces).
        let dt = deltaTime.clamped(to: (1 / 240)...(1 / 60))

        let freeSize = CGFloat(settings.pointerSize)
        var desiredCenter = physicalPosition
        var desiredSize = CGSize(width: freeSize, height: freeSize)
        var desiredRadius = freeSize * settings.shape.cornerRadiusFraction
        var desiredControlAmount: CGFloat = 0
        var desiredTextAmount: CGFloat = 0

        if let target {
            switch target.kind {
            case .control:
                let padding = CGFloat(settings.controlPadding)
                let targetFrame = target.frame.insetBy(dx: -padding, dy: -padding)
                desiredCenter = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
                desiredSize = targetFrame.size
                desiredRadius = min(
                    target.cornerRadius + padding,
                    min(targetFrame.width, targetFrame.height) / 2
                )
                desiredControlAmount = 1
            case .text:
                desiredSize = CGSize(width: 10, height: 23)
                desiredRadius = 1.5
                desiredTextAmount = 1
            }
        }

        if !initialized {
            center = desiredCenter
            size = desiredSize
            cornerRadius = desiredRadius
            initialized = true
        }

        let isSnappedToControl = target?.kind == .control
        if usesPointerInertia || isSnappedToControl {
            spring(
                value: &center.x,
                velocity: &centerVelocity.dx,
                target: desiredCenter.x,
                stiffness: target == nil ? 1_850 : 900,
                damping: target == nil ? 72 : 48,
                dt: dt
            )
            spring(
                value: &center.y,
                velocity: &centerVelocity.dy,
                target: desiredCenter.y,
                stiffness: target == nil ? 1_850 : 900,
                damping: target == nil ? 72 : 48,
                dt: dt
            )
        } else {
            center = desiredCenter
            centerVelocity = .zero
        }
        spring(
            value: &size.width, velocity: &sizeVelocity.dx, target: desiredSize.width, stiffness: 720, damping: 44,
            dt: dt)
        spring(
            value: &size.height, velocity: &sizeVelocity.dy, target: desiredSize.height, stiffness: 720, damping: 44,
            dt: dt)
        spring(
            value: &cornerRadius, velocity: &cornerVelocity, target: desiredRadius, stiffness: 720, damping: 44, dt: dt)

        controlAmount.approach(desiredControlAmount, rate: 23, dt: dt)
        textAmount.approach(desiredTextAmount, rate: 27, dt: dt)
        pressedAmount.approach(isPressed ? 1 : 0, rate: isPressed ? 34 : 22, dt: dt)
        opacity.approach(isVisible ? 1 : 0, rate: isVisible ? 30 : 7, dt: dt)

        let pressScale = 1 - (0.13 * pressedAmount * (1 - (0.70 * controlAmount)))
        let visualSize = CGSize(
            width: max(2, size.width * pressScale),
            height: max(2, size.height * pressScale)
        )
        let quartzShapeFrame = CGRect(
            x: center.x - visualSize.width / 2,
            y: center.y - visualSize.height / 2,
            width: visualSize.width,
            height: visualSize.height
        )
        let quartzWindowFrame = quartzShapeFrame.insetBy(dx: -Self.padding, dy: -Self.padding)
        let appKitFrame = Self.appKitRect(fromQuartzRect: quartzWindowFrame)

        Self.currentCornerRadius = max(0, cornerRadius * pressScale)
        cursorView.drawingState = CursorDrawingState(
            controlAmount: controlAmount,
            textAmount: textAmount,
            pressedAmount: pressedAmount
        )
        panel.alphaValue = opacity
        panel.setFrame(appKitFrame, display: false)

        cursorView.needsDisplay = true
    }

    func applySettings(_ settings: CursorAppearanceSettings) {
        self.settings = settings
        cursorView.pointerSettings = settings

    }

    func show() {
        panel.orderFrontRegardless()
    }

    func setDormant() {
        panel.alphaValue = 0
    }

    func hide() {
        panel.orderOut(nil)
    }

    private static func appKitRect(fromQuartzRect rect: CGRect) -> CGRect {
        let primaryScreenTop = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(
            x: rect.minX,
            y: primaryScreenTop - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func spring(
        value: inout CGFloat,
        velocity: inout CGFloat,
        target: CGFloat,
        stiffness: CGFloat,
        damping: CGFloat,
        dt: CGFloat
    ) {
        let acceleration = ((target - value) * stiffness) - (velocity * damping)
        velocity += acceleration * dt
        value += velocity * dt
    }
}

private extension CGFloat {
    mutating func approach(_ target: CGFloat, rate: CGFloat, dt: CGFloat) {
        let amount = 1 - exp(-rate * dt)
        self += (target - self) * amount
    }
}
