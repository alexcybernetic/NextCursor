import AppKit
import ApplicationServices
import CoreGraphics
import QuartzCore

final class CursorEngine {
    private let detector = AccessibilityTargetDetector()
    private let systemCursor = SystemCursorController()
    private var overlay: CursorOverlay?
    private var frameTimer: Timer?
    private var frameTimerInterval: TimeInterval = 0
    private var detectionAccumulator: CFTimeInterval = 0
    private var lastFrameTime: CFTimeInterval = 0
    private var lastActivityTime: CFTimeInterval = 0
    private var lastPosition = CGPoint.zero
    private var latestTarget: CursorTarget?
    private var wasPressed = false
    private var isDeepIdle = false
    private var usesPointerInertia = false

    private(set) var isRunning = false

    func setPointerInertiaEnabled(_ enabled: Bool) {
        usesPointerInertia = enabled
    }

    func start() {
        guard !isRunning else { return }

        let now = CACurrentMediaTime()
        let position = currentPointerPosition()
        let overlay = CursorOverlay(initialPosition: position)
        self.overlay = overlay
        lastPosition = position
        lastFrameTime = now
        lastActivityTime = now
        detectionAccumulator = 1
        latestTarget = nil
        isDeepIdle = false
        isRunning = true

        overlay.show()
        hideSystemCursor()

        scheduleFrameTimer(interval: 1.0 / 120.0)
    }

    func stop() {
        guard isRunning else {
            showSystemCursor()
            return
        }

        isRunning = false
        frameTimer?.invalidate()
        frameTimer = nil
        frameTimerInterval = 0
        latestTarget = nil

        // Restore the usable system pointer before removing our overlay so
        // there is never a frame where the user has no visible cursor.
        showSystemCursor()
        overlay?.hide()
        overlay = nil
    }

    private func tick() {
        guard isRunning, let overlay else { return }

        let now = CACurrentMediaTime()
        let dt = min(max(now - lastFrameTime, 1.0 / 240.0), 1.0 / 24.0)
        lastFrameTime = now

        let position = currentPointerPosition()
        let moved = hypot(position.x - lastPosition.x, position.y - lastPosition.y) > 0.05
        let isPressed = CGEventSource.buttonState(.combinedSessionState, button: .left)
            || CGEventSource.buttonState(.combinedSessionState, button: .right)
        let pressChanged = isPressed != wasPressed
        let scrolled = recentScrollActivity()

        systemCursor.maintainHiddenState(force: pressChanged)

        if moved || isPressed || pressChanged || scrolled {
            lastActivityTime = now
        }
        lastPosition = position
        wasPressed = isPressed

        let idleDuration = now - lastActivityTime
        if idleDuration > 3.2, !moved, !isPressed, !pressChanged, !scrolled {
            if !isDeepIdle {
                overlay.setDormant()
                isDeepIdle = true
                scheduleFrameTimer(interval: 1.0 / 30.0)
            }
            return
        }
        if isDeepIdle {
            isDeepIdle = false
            scheduleFrameTimer(interval: 1.0 / 120.0)
        }

        detectionAccumulator += dt
        let isVisible = idleDuration < 2.2
        if isVisible, detectionAccumulator >= (1.0 / 30.0) {
            detectionAccumulator = 0
            detector.detect(at: position) { [weak self] result in
                self?.acceptDetection(result)
            }
        }

        let target = validTarget(at: position)
        overlay.update(
            physicalPosition: position,
            target: target,
            usesPointerInertia: usesPointerInertia,
            isPressed: isPressed,
            isVisible: isVisible,
            deltaTime: CGFloat(dt)
        )
    }

    private func scheduleFrameTimer(interval: TimeInterval) {
        guard isRunning, abs(frameTimerInterval - interval) > 0.000_1 else { return }

        frameTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
        frameTimerInterval = interval
    }

    private func acceptDetection(_ result: TargetDetectionResult) {
        guard isRunning else { return }

        let distance = hypot(
            result.sampledPoint.x - lastPosition.x,
            result.sampledPoint.y - lastPosition.y
        )

        // AX hit-testing crosses process boundaries. Ignore a result if the
        // physical pointer has moved far enough that the answer is stale.
        guard distance < 10 else { return }
        latestTarget = result.target
    }

    private func validTarget(at point: CGPoint) -> CursorTarget? {
        guard let target = latestTarget else { return nil }
        return target.frame.insetBy(dx: -1.5, dy: -1.5).contains(point) ? target : nil
    }

    private func recentScrollActivity() -> Bool {
        CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: .scrollWheel
        ) < 0.12
    }

    private func currentPointerPosition() -> CGPoint {
        // AX and CGEvent use Quartz global coordinates (origin at the upper
        // left of the primary display), so no per-display conversion is needed.
        CGEvent(source: nil)?.location ?? .zero
    }

    private func hideSystemCursor() {
        systemCursor.hide()
    }

    private func showSystemCursor() {
        systemCursor.show()
    }

    deinit {
        stop()
    }
}
