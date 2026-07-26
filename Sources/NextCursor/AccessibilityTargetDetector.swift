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

    private func findTarget(at point: CGPoint) -> CursorTarget? {
        var hitElement: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(point.x),
            Float(point.y),
            &hitElement
        )

        guard error == .success, var element = hitElement else { return nil }

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
