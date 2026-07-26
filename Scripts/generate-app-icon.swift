#!/usr/bin/env swift

import AppKit
import Foundation

private let canvasSize: CGFloat = 1024

private func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

private struct Vector {
    var x: CGFloat
    var y: CGFloat

    var point: NSPoint { NSPoint(x: x, y: y) }

    static func direction(degrees: CGFloat) -> Vector {
        let radians = degrees * .pi / 180
        return Vector(x: cos(radians), y: sin(radians))
    }

    static func + (lhs: Vector, rhs: Vector) -> Vector {
        Vector(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func - (lhs: Vector, rhs: Vector) -> Vector {
        Vector(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func * (lhs: Vector, rhs: CGFloat) -> Vector {
        Vector(x: lhs.x * rhs, y: lhs.y * rhs)
    }
}

private func circle(at center: Vector, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(
        ovalIn: NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
    )
}

private func drawIcon() {
    let backgroundRect = NSRect(x: 72, y: 72, width: 880, height: 880)
    let background = NSBezierPath(roundedRect: backgroundRect, xRadius: 208, yRadius: 208)

    // The fill is flat. The shadow sits behind it and shapes the silhouette in
    // the Dock rather than shading the surface.
    NSGraphicsContext.saveGraphicsState()
    let backgroundShadow = NSShadow()
    backgroundShadow.shadowColor = color(0x7A2E00, alpha: 0.30)
    backgroundShadow.shadowBlurRadius = 44
    backgroundShadow.shadowOffset = NSSize(width: 0, height: -20)
    backgroundShadow.set()
    color(0xFF7A18).setFill()
    background.fill()
    NSGraphicsContext.restoreGraphicsState()

    let head = Vector(x: 608, y: 598)
    let headRadius: CGFloat = 146
    let travelDegrees: CGFloat = 45

    let travel = Vector.direction(degrees: travelDegrees)
    let across = Vector.direction(degrees: travelDegrees + 90)

    NSColor.white.setFill()
    circle(at: head, radius: headRadius).fill()

    // The tail is detached rather than fused to the head. Any tail joined to a
    // circle is bounded below by the circle's own width — tangent edges cannot
    // be narrower than its diameter — so a fused tail always collapses the
    // silhouette into a teardrop and the circular pointer stops reading.
    let gap: CGFloat = 32
    let streakLength: CGFloat = 215
    let streakHalfWidth: CGFloat = 60

    // Offset by the cap radius as well as the gap. Measuring to the cap centre
    // instead buries its leading edge inside the head and the two shapes fuse.
    let streakStart = head - travel * (headRadius + gap + streakHalfWidth)
    let streakTip = streakStart - travel * streakLength

    // Blunt where it leaves the head, tapering to a point. A shape pointed at
    // both ends reads as a detached leaf rather than as a trail.
    let streak = NSBezierPath()
    streak.appendArc(
        withCenter: streakStart.point,
        radius: streakHalfWidth,
        startAngle: travelDegrees + 90,
        endAngle: travelDegrees - 90,
        clockwise: true
    )
    streak.curve(
        to: streakTip.point,
        controlPoint1: (streakStart - across * streakHalfWidth - travel * (streakLength * 0.35)).point,
        controlPoint2: (streakTip + travel * (streakLength * 0.38) - across * (streakHalfWidth * 0.42)).point
    )
    streak.curve(
        to: (streakStart + across * streakHalfWidth).point,
        controlPoint1: (streakTip + travel * (streakLength * 0.38) + across * (streakHalfWidth * 0.42)).point,
        controlPoint2: (streakStart + across * streakHalfWidth - travel * (streakLength * 0.35)).point
    )
    streak.close()
    streak.fill()
}

private func pngData(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: size * 4,
        bitsPerPixel: 32
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    let previousContext = NSGraphicsContext.current
    NSGraphicsContext.current = context
    context.cgContext.setAllowsAntialiasing(true)
    context.cgContext.setShouldAntialias(true)
    context.cgContext.scaleBy(x: CGFloat(size) / canvasSize, y: CGFloat(size) / canvasSize)
    drawIcon()
    context.flushGraphics()
    NSGraphicsContext.current = previousContext

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

private func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw CocoaError(.executableNotLoadable)
    }
}

let fileManager = FileManager.default
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let projectRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let resources = projectRoot.appendingPathComponent("Resources", isDirectory: true)
let previewURL = resources.appendingPathComponent("NextCursorIcon.png")
let iconURL = resources.appendingPathComponent("NextCursor.icns")
let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
let iconset = temporaryRoot.appendingPathComponent("NextCursor.iconset", isDirectory: true)

let iconFiles: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

do {
    try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: temporaryRoot) }

    try pngData(size: 1024).write(to: previewURL, options: .atomic)
    for iconFile in iconFiles {
        try pngData(size: iconFile.size)
            .write(to: iconset.appendingPathComponent(iconFile.name), options: .atomic)
    }

    try? fileManager.removeItem(at: iconURL)
    try run("/usr/bin/iconutil", ["--convert", "icns", "--output", iconURL.path, iconset.path])
    print("Generated \(previewURL.path)")
    print("Generated \(iconURL.path)")
} catch {
    FileHandle.standardError.write(Data("Could not generate app icon: \(error)\n".utf8))
    exit(1)
}
