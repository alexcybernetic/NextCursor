import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

final class AccessibilityTargetDetector {
    private let queue = DispatchQueue(
        label: "com.nextcursor.NextCursor.accessibility",
        qos: .userInteractive
    )
    private let systemWideElement = AXUIElementCreateSystemWide()
    private var requestInFlight = false

    func detect(at point: CGPoint, completion: @escaping (TargetDetectionResult) -> Void) {
        guard !requestInFlight else { return }

        // Checked here, on the main thread, before any hit test is issued.
        // AXUIElementCopyElementAtPosition asks the owning process to hit-test
        // itself, and when that process is this one the work lands on the
        // detector's background queue and re-enters AppKit and SwiftUI layout
        // off the main thread, which faults inside accessibility geometry.
        // Inspecting the element afterwards cannot help: the crash happens
        // during the hit test, before there is a result to inspect.
        guard !Self.isPointOverOwnWindow(point) else {
            completion(TargetDetectionResult(sampledPoint: point, target: nil))
            return
        }

        requestInFlight = true

        queue.async { [weak self] in
            let target = self?.findTarget(at: point)
            let result = TargetDetectionResult(sampledPoint: point, target: target)

            DispatchQueue.main.async {
                self?.requestInFlight = false
                completion(result)
            }
        }
    }

    /// Whether the pointer is over one of this application's own windows.
    ///
    /// The cursor overlay is excluded: it tracks the pointer, so it is always
    /// underneath it, and treating it as our own window would disable
    /// detection everywhere. It takes no mouse events and is not hit-tested.
    private static func isPointOverOwnWindow(_ point: CGPoint) -> Bool {
        // AX reports Quartz coordinates, with the origin at the top left of the
        // primary display; NSWindow frames are AppKit's, with the origin at the
        // bottom left.
        let primaryScreenTop = NSScreen.screens.first?.frame.maxY ?? 0
        let appKitPoint = CGPoint(x: point.x, y: primaryScreenTop - point.y)

        return NSApp.windows.contains { window in
            window.isVisible
                && !window.ignoresMouseEvents
                && window.frame.contains(appKitPoint)
        }
    }

    private func findTarget(at point: CGPoint) -> CursorTarget? {
        var hitElement: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(point.x),
            Float(point.y),
            &hitElement
        )

        guard error == .success, var element = hitElement else { return nil }

        // Never inspect this process's own interface. Reading an accessibility
        // tree makes the owning process compute frames on whichever thread
        // services the request, and this detector runs on a background queue.
        // For another application that work happens over there; for our own it
        // re-enters AppKit and SwiftUI layout off the main thread, which faults
        // inside accessibility frame computation. Snapping to NextCursor's own
        // menu bar item or settings window would be wrong regardless.
        var elementProcessIdentifier: pid_t = 0
        guard AXUIElementGetPid(element, &elementProcessIdentifier) == .success,
            elementProcessIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            return nil
        }

        var textCandidate: CursorTarget?
        var visited = Set<Int>()

        for _ in 0..<7 {
            let identity = Int(truncatingIfNeeded: CFHash(element))
            guard visited.insert(identity).inserted else { break }

            let role = stringAttribute(element, kAXRoleAttribute as String) ?? ""
            let frame = frameAttribute(element)

            if let frame, isValid(frame: frame), frame.insetBy(dx: -1, dy: -1).contains(point) {
                if isMorphableControlFrame(frame),
                    isInteractive(element: element, role: role),
                    isEnabled(element)
                {
                    return CursorTarget(
                        kind: .control,
                        frame: frame,
                        cornerRadius: suggestedCornerRadius(for: role, frame: frame),
                        role: role,
                        identity: identity
                    )
                }

                if textCandidate == nil, isTextRole(role) {
                    textCandidate = CursorTarget(
                        kind: .text,
                        frame: frame,
                        cornerRadius: 1.5,
                        role: role,
                        identity: identity
                    )
                }
            }

            guard let parent = elementAttribute(element, kAXParentAttribute as String) else {
                break
            }
            element = parent
        }

        return textCandidate
    }

    private func isInteractive(element: AXUIElement, role: String) -> Bool {
        let knownRoles: Set<String> = [
            "AXButton",
            "AXCheckBox",
            "AXRadioButton",
            "AXPopUpButton",
            "AXMenuButton",
            "AXDisclosureTriangle",
            "AXLink",
            "AXMenuItem",
            "AXMenuBarItem",
            "AXDockItem",
            "AXTab",
            "AXSwitch",
            "AXColorWell",
            "AXComboBox",
        ]

        if knownRoles.contains(role) {
            return true
        }

        // Custom controls often expose only an AXPress action. Reading the
        // action list does not perform the action or inspect the control value.
        var actionNames: CFArray?
        guard AXUIElementCopyActionNames(element, &actionNames) == .success,
            let names = actionNames as? [String]
        else {
            return false
        }
        return names.contains(kAXPressAction as String)
    }

    private func isTextRole(_ role: String) -> Bool {
        switch role {
        case "AXTextField", "AXTextArea", "AXStaticText":
            return true
        default:
            return false
        }
    }

    private func isEnabled(_ element: AXUIElement) -> Bool {
        guard let value = attribute(element, kAXEnabledAttribute as String) else {
            return true
        }
        return (value as? Bool) ?? true
    }

    private func isValid(frame: CGRect) -> Bool {
        frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
            && frame.width >= 3
            && frame.height >= 3
    }

    private func isMorphableControlFrame(_ frame: CGRect) -> Bool {
        frame.width <= 560 && frame.height <= 140
    }

    private func suggestedCornerRadius(for role: String, frame: CGRect) -> CGFloat {
        let shortestSide = min(frame.width, frame.height)

        switch role {
        case "AXRadioButton", "AXColorWell":
            return shortestSide / 2
        case "AXMenuItem", "AXMenuBarItem", "AXDockItem":
            return min(8, shortestSide * 0.28)
        default:
            return min(12, shortestSide * 0.32)
        }
    }

    private func frameAttribute(_ element: AXUIElement) -> CGRect? {
        guard let positionValue = attribute(element, kAXPositionAttribute as String),
            let sizeValue = attribute(element, kAXSizeAttribute as String),
            CFGetTypeID(positionValue) == AXValueGetTypeID(),
            CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        let positionAXValue = positionValue as! AXValue
        let sizeAXValue = sizeValue as! AXValue

        guard AXValueGetValue(positionAXValue, .cgPoint, &position),
            AXValueGetValue(sizeAXValue, .cgSize, &size)
        else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    private func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }
}
