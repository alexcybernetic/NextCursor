import AppKit

/// The comet from the app icon, drawn at any size.
///
/// The proportions mirror `Scripts/generate-app-icon.swift`, normalised so the
/// mark's bounding box is the unit square. Changing one without the other
/// leaves the menu bar and the app icon showing different marks.
enum CometMark {
    private static let headCenter = CGPoint(x: 0.686, y: 0.686)
    private static let headRadius: CGFloat = 0.3127
    private static let travelDegrees: CGFloat = 45
    private static let gap: CGFloat = 0.0685
    private static let streakHalfWidth: CGFloat = 0.1285
    private static let streakLength: CGFloat = 0.4605

    /// A template image for the status item.
    ///
    /// Template images are recoloured by AppKit to suit the menu bar, so the
    /// mark is drawn in flat black and the orange lives only in the app icon.
    static func statusItemImage(size: CGFloat = 18, isActive: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let markRect = rect.insetBy(dx: size * 0.06, dy: size * 0.06)
            let head = headPath(in: markRect)
            let streak = streakPath(in: markRect)

            if isActive {
                NSColor.black.setFill()
                head.fill()
                streak.fill()
            } else {
                // Hollow while inactive, so the menu bar distinguishes running
                // from stopped without a second glyph.
                let lineWidth = max(1, size * 0.075)
                NSColor.black.setStroke()
                for path in [head, streak] {
                    path.lineWidth = lineWidth
                    path.stroke()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    static func headPath(in rect: CGRect) -> NSBezierPath {
        let center = point(headCenter, in: rect)
        let radius = headRadius * min(rect.width, rect.height)
        return NSBezierPath(
            ovalIn: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
    }

    /// Blunt where it leaves the head, tapering to a point. Detached from the
    /// head: a tail joined to a circle cannot be narrower than that circle, so
    /// a fused one collapses the silhouette into a teardrop.
    static func streakPath(in rect: CGRect) -> NSBezierPath {
        let scale = min(rect.width, rect.height)
        let travel = direction(travelDegrees)
        let center = point(headCenter, in: rect)
        let halfWidth = streakHalfWidth * scale
        let length = streakLength * scale
        let offset = (headRadius * scale) + (gap * scale) + halfWidth

        let start = CGPoint(
            x: center.x - travel.dx * offset,
            y: center.y - travel.dy * offset
        )
        let tip = CGPoint(
            x: start.x - travel.dx * length,
            y: start.y - travel.dy * length
        )
        let across = direction(travelDegrees + 90)

        func shifted(_ origin: CGPoint, along vector: CGVector, by amount: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + vector.dx * amount, y: origin.y + vector.dy * amount)
        }

        let path = NSBezierPath()
        path.appendArc(
            withCenter: start,
            radius: halfWidth,
            startAngle: travelDegrees + 90,
            endAngle: travelDegrees - 90,
            clockwise: true
        )
        path.curve(
            to: tip,
            controlPoint1: shifted(
                shifted(start, along: across, by: -halfWidth),
                along: travel,
                by: -length * 0.35
            ),
            controlPoint2: shifted(
                shifted(tip, along: travel, by: length * 0.38),
                along: across,
                by: -halfWidth * 0.42
            )
        )
        path.curve(
            to: shifted(start, along: across, by: halfWidth),
            controlPoint1: shifted(
                shifted(tip, along: travel, by: length * 0.38),
                along: across,
                by: halfWidth * 0.42
            ),
            controlPoint2: shifted(
                shifted(start, along: across, by: halfWidth),
                along: travel,
                by: -length * 0.35
            )
        )
        path.close()
        return path
    }

    private static func point(_ unit: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + unit.x * rect.width, y: rect.minY + unit.y * rect.height)
    }

    private static func direction(_ degrees: CGFloat) -> CGVector {
        let radians = degrees * .pi / 180
        return CGVector(dx: cos(radians), dy: sin(radians))
    }
}
