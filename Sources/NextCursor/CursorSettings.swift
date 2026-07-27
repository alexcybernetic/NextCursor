import AppKit
import SwiftUI

/// A colour in a form that survives a round trip through user defaults.
struct StoredColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(color: Color) {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .white
        red = Double(resolved.redComponent)
        green = Double(resolved.greenComponent)
        blue = Double(resolved.blueComponent)
        alpha = Double(resolved.alphaComponent)
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    func normalized() -> StoredColor {
        StoredColor(
            red: red.clamped(to: 0...1),
            green: green.clamped(to: 0...1),
            blue: blue.clamped(to: 0...1),
            alpha: alpha.clamped(to: 0...1)
        )
    }

    /// Component-wise blend, used to cross the free pointer's colour into the
    /// snapped control's colour as the pointer morphs.
    func blended(toward other: StoredColor, amount: Double) -> StoredColor {
        let t = amount.clamped(to: 0...1)
        return StoredColor(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t,
            alpha: alpha + (other.alpha - alpha) * t
        )
    }
}

/// The shape of the free pointer.
///
/// Circle, rounded square, and square are all rounded rectangles differing only
/// in corner radius, so they morph into a snapped control through the existing
/// corner-radius spring. The polygons cannot morph that way and are instead
/// cross-faded against the control shape.
enum CursorShapeKind: String, CaseIterable, Codable, Identifiable {
    case circle
    case roundedSquare
    case square
    case triangle
    case octagon
    case star
    case heart

    var id: Self { self }

    var displayName: String {
        switch self {
        case .circle: return "Circle"
        case .roundedSquare: return "Rounded"
        case .square: return "Square"
        case .triangle: return "Triangle"
        case .octagon: return "Octagon"
        case .star: return "Star"
        case .heart: return "Heart"
        }
    }

    /// Whether the shape is expressible as a rounded rectangle.
    var isRoundedRectangle: Bool {
        switch self {
        case .circle, .roundedSquare, .square: return true
        case .triangle, .octagon, .star, .heart: return false
        }
    }

    /// Corner radius for the rounded-rectangle shapes, as a fraction of the
    /// shorter side. Meaningless for the polygons.
    var cornerRadiusFraction: CGFloat {
        switch self {
        case .circle: return 0.5
        case .roundedSquare: return 0.28
        case .square: return 0
        case .triangle, .octagon, .star, .heart: return 0
        }
    }

    /// Vertices for the polygon shapes, in the supplied rectangle. Empty for
    /// the rounded-rectangle shapes.
    /// The outline for every shape that is not a rounded rectangle. Nil for
    /// the rounded-rectangle family, which is drawn through the existing
    /// corner-radius spring instead.
    func customPath(in rect: CGRect) -> NSBezierPath? {
        if self == .heart { return Self.heartPath(in: rect) }

        let points = polygonPoints(in: rect)
        guard points.count >= 3 else { return nil }

        let path = NSBezierPath()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.line(to: point)
        }
        path.close()
        path.lineJoinStyle = .round
        return path
    }

    func polygonPoints(in rect: CGRect) -> [CGPoint] {
        switch self {
        case .circle, .roundedSquare, .square, .heart:
            return []
        case .triangle:
            return Self.regularPolygonPoints(sides: 3, in: rect)
        case .octagon:
            return Self.regularPolygonPoints(sides: 8, in: rect)
        case .star:
            return Self.starPoints(points: 5, innerRatio: 0.42, in: rect)
        }
    }

    /// Built from cubic curves rather than vertices, so it cannot come from
    /// `polygonPoints`. Expressed in a unit square and scaled into `rect`.
    private static func heartPath(in rect: CGRect) -> NSBezierPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        let path = NSBezierPath()
        path.move(to: point(0.5, 0.03))
        path.curve(
            to: point(0.03, 0.60),
            controlPoint1: point(0.30, 0.22),
            controlPoint2: point(0.03, 0.40)
        )
        path.curve(
            to: point(0.5, 0.85),
            controlPoint1: point(0.03, 0.84),
            controlPoint2: point(0.26, 1.0)
        )
        path.curve(
            to: point(0.97, 0.60),
            controlPoint1: point(0.74, 1.0),
            controlPoint2: point(0.97, 0.84)
        )
        path.curve(
            to: point(0.5, 0.03),
            controlPoint1: point(0.97, 0.40),
            controlPoint2: point(0.70, 0.22)
        )
        path.close()
        path.lineJoinStyle = .round
        return path
    }

    private static func regularPolygonPoints(sides: Int, in rect: CGRect) -> [CGPoint] {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // Start at the top so triangles and octagons sit upright.
        let start = CGFloat.pi / 2
        return (0..<sides).map { index in
            let angle = start + (CGFloat(index) * 2 * .pi / CGFloat(sides))
            return CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }

    private static func starPoints(
        points: Int,
        innerRatio: CGFloat,
        in rect: CGRect
    ) -> [CGPoint] {
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * innerRatio
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let start = CGFloat.pi / 2
        return (0..<(points * 2)).map { index in
            let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
            let angle = start + (CGFloat(index) * .pi / CGFloat(points))
            return CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }
}

struct CursorAppearanceSettings: Codable, Equatable {
    static let currentVersion = 5

    static let sizeRange: ClosedRange<Double> = 10...44
    static let borderWidthRange: ClosedRange<Double> = 0...6
    static let controlBorderWidthRange: ClosedRange<Double> = 0...4
    static let controlPaddingRange: ClosedRange<Double> = 0...10

    var version = currentVersion
    var shape: CursorShapeKind = .circle
    var pointerSize = 20.0

    // The pointer sits over content whose brightness is unknown, so each
    // appearance carries its own fill and border rather than one colour being
    // reused for both.
    var lightFill = StoredColor(red: 0.34, green: 0.34, blue: 0.34, alpha: 0.78)
    var darkFill = StoredColor(red: 0.78, green: 0.78, blue: 0.78, alpha: 0.78)
    var lightBorder = StoredColor(red: 1, green: 1, blue: 1, alpha: 0.55)
    var darkBorder = StoredColor(red: 0, green: 0, blue: 0, alpha: 0.45)

    /// A border is on by default. A fill alone can be made invisible against
    /// content of a similar brightness, and the border is what guarantees the
    /// pointer stays findable whatever the user picks.
    var borderWidth = 1.0

    // The appearance the pointer takes when it snaps to a control.
    var lightControlFill = StoredColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 0.15)
    var darkControlFill = StoredColor(red: 0.92, green: 0.92, blue: 0.92, alpha: 0.20)
    var lightControlBorder = StoredColor(red: 0, green: 0, blue: 0, alpha: 0.11)
    var darkControlBorder = StoredColor(red: 1, green: 1, blue: 1, alpha: 0.11)
    var controlBorderWidth = 0.75

    /// How far the snapped shape extends beyond the control's own bounds.
    var controlPadding = 3.0

    var usesPointerInertia = false

    func fill(isDark: Bool) -> StoredColor { isDark ? darkFill : lightFill }
    func border(isDark: Bool) -> StoredColor { isDark ? darkBorder : lightBorder }
    func controlFill(isDark: Bool) -> StoredColor {
        isDark ? darkControlFill : lightControlFill
    }
    func controlBorder(isDark: Bool) -> StoredColor {
        isDark ? darkControlBorder : lightControlBorder
    }

    /// Brings a stored payload forward to the current version.
    ///
    /// Runs only on load. `normalized()` stamps the current version, so it
    /// cannot double as the migration point: it would erase the very field
    /// that says which migrations are still owed.
    func migrated() -> CursorAppearanceSettings {
        var result = self
        // Versions 1 to 4 carried liquid glass settings. NSGlassEffectView
        // rendered nothing usable at pointer size, so those fields are dropped
        // wherever they appear.
        result.version = Self.currentVersion
        return result
    }

    func normalized() -> CursorAppearanceSettings {
        var result = self
        result.version = Self.currentVersion
        result.pointerSize = pointerSize.clamped(to: Self.sizeRange)
        result.borderWidth = borderWidth.clamped(to: Self.borderWidthRange)
        result.controlBorderWidth = controlBorderWidth.clamped(
            to: Self.controlBorderWidthRange
        )
        result.controlPadding = controlPadding.clamped(to: Self.controlPaddingRange)
        result.lightFill = lightFill.normalized()
        result.darkFill = darkFill.normalized()
        result.lightBorder = lightBorder.normalized()
        result.darkBorder = darkBorder.normalized()
        result.lightControlFill = lightControlFill.normalized()
        result.darkControlFill = darkControlFill.normalized()
        result.lightControlBorder = lightControlBorder.normalized()
        result.darkControlBorder = darkControlBorder.normalized()
        return result
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}


extension CursorAppearanceSettings {
    private enum CodingKeys: String, CodingKey {
        case version, shape, pointerSize
        case lightFill, darkFill, lightBorder, darkBorder, borderWidth
        case lightControlFill, darkControlFill, lightControlBorder, darkControlBorder
        case controlBorderWidth, controlPadding
        case usesPointerInertia
    }

    /// Decoded field by field with a default for anything absent.
    ///
    /// The synthesized conformance requires every key to be present, so adding
    /// a property would make an older stored payload fail to decode. The store
    /// falls back to defaults on failure, which silently discards everything
    /// the user had configured.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = CursorAppearanceSettings()

        func value<T: Decodable>(_ key: CodingKeys, _ defaultValue: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) as? T ?? defaultValue
        }

        self.init()
        version = value(.version, fallback.version)
        shape = value(.shape, fallback.shape)
        pointerSize = value(.pointerSize, fallback.pointerSize)
        lightFill = value(.lightFill, fallback.lightFill)
        darkFill = value(.darkFill, fallback.darkFill)
        lightBorder = value(.lightBorder, fallback.lightBorder)
        darkBorder = value(.darkBorder, fallback.darkBorder)
        borderWidth = value(.borderWidth, fallback.borderWidth)
        lightControlFill = value(.lightControlFill, fallback.lightControlFill)
        darkControlFill = value(.darkControlFill, fallback.darkControlFill)
        lightControlBorder = value(.lightControlBorder, fallback.lightControlBorder)
        darkControlBorder = value(.darkControlBorder, fallback.darkControlBorder)
        controlBorderWidth = value(.controlBorderWidth, fallback.controlBorderWidth)
        controlPadding = value(.controlPadding, fallback.controlPadding)
        usesPointerInertia = value(.usesPointerInertia, fallback.usesPointerInertia)
    }
}
