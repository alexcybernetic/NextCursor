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

private func drawIcon() {
    let backgroundRect = NSRect(x: 72, y: 72, width: 880, height: 880)
    let background = NSBezierPath(roundedRect: backgroundRect, xRadius: 208, yRadius: 208)

    NSGraphicsContext.saveGraphicsState()
    let backgroundShadow = NSShadow()
    backgroundShadow.shadowColor = color(0x11142F, alpha: 0.38)
    backgroundShadow.shadowBlurRadius = 48
    backgroundShadow.shadowOffset = NSSize(width: 0, height: -22)
    backgroundShadow.set()
    color(0x4432A5).setFill()
    background.fill()
    NSGraphicsContext.restoreGraphicsState()

    let backgroundGradient = NSGradient(
        colorsAndLocations:
            (color(0x8797FF), 0),
            (color(0x665AEF), 0.46),
            (color(0x34206F), 1)
    )!
    backgroundGradient.draw(in: background, angle: -56)

    NSGraphicsContext.saveGraphicsState()
    background.addClip()

    let upperGlow = NSGradient(
        starting: NSColor.white.withAlphaComponent(0.34),
        ending: NSColor.white.withAlphaComponent(0)
    )!
    upperGlow.draw(
        fromCenter: NSPoint(x: 220, y: 860),
        radius: 0,
        toCenter: NSPoint(x: 220, y: 860),
        radius: 660,
        options: [.drawsAfterEndingLocation]
    )

    let lowerGlow = NSGradient(
        starting: color(0x39D8FF, alpha: 0.28),
        ending: color(0x39D8FF, alpha: 0)
    )!
    lowerGlow.draw(
        fromCenter: NSPoint(x: 820, y: 180),
        radius: 0,
        toCenter: NSPoint(x: 820, y: 180),
        radius: 560,
        options: [.drawsAfterEndingLocation]
    )

    let sheen = NSBezierPath()
    sheen.move(to: NSPoint(x: 98, y: 750))
    sheen.curve(
        to: NSPoint(x: 860, y: 936),
        controlPoint1: NSPoint(x: 330, y: 950),
        controlPoint2: NSPoint(x: 650, y: 972)
    )
    sheen.line(to: NSPoint(x: 954, y: 954))
    sheen.line(to: NSPoint(x: 72, y: 954))
    sheen.close()
    NSColor.white.withAlphaComponent(0.055).setFill()
    sheen.fill()

    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    color(0xFFFFFF, alpha: 0.24).setStroke()
    background.lineWidth = 5
    background.stroke()
    NSGraphicsContext.restoreGraphicsState()

    let haloRect = NSRect(x: 184, y: 326, width: 656, height: 372)
    let halo = NSBezierPath(roundedRect: haloRect, xRadius: 158, yRadius: 158)
    NSGraphicsContext.saveGraphicsState()
    let haloShadow = NSShadow()
    haloShadow.shadowColor = color(0x9EEBFF, alpha: 0.32)
    haloShadow.shadowBlurRadius = 42
    haloShadow.shadowOffset = .zero
    haloShadow.set()
    color(0xDDF9FF, alpha: 0.12).setStroke()
    halo.lineWidth = 18
    halo.stroke()
    NSGraphicsContext.restoreGraphicsState()

    let controlRect = NSRect(x: 210, y: 350, width: 604, height: 324)
    let control = NSBezierPath(roundedRect: controlRect, xRadius: 138, yRadius: 138)

    NSGraphicsContext.saveGraphicsState()
    let controlShadow = NSShadow()
    controlShadow.shadowColor = color(0x171238, alpha: 0.24)
    controlShadow.shadowBlurRadius = 30
    controlShadow.shadowOffset = NSSize(width: 0, height: -10)
    controlShadow.set()
    color(0x241B62, alpha: 0.18).setFill()
    control.fill()
    NSGraphicsContext.restoreGraphicsState()

    let controlGradient = NSGradient(
        starting: NSColor.white.withAlphaComponent(0.18),
        ending: NSColor.white.withAlphaComponent(0.055)
    )!
    controlGradient.draw(in: control, angle: 90)

    color(0xFFFFFF, alpha: 0.46).setStroke()
    control.lineWidth = 10
    control.stroke()

    let innerHighlightRect = controlRect.insetBy(dx: 15, dy: 15)
    let innerHighlight = NSBezierPath(roundedRect: innerHighlightRect, xRadius: 123, yRadius: 123)
    color(0xBEEFFF, alpha: 0.14).setStroke()
    innerHighlight.lineWidth = 4
    innerHighlight.stroke()

    let cursorRect = NSRect(x: 397, y: 397, width: 230, height: 230)
    let cursor = NSBezierPath(ovalIn: cursorRect)

    NSGraphicsContext.saveGraphicsState()
    let cursorGlow = NSShadow()
    cursorGlow.shadowColor = color(0xAAEEFF, alpha: 0.58)
    cursorGlow.shadowBlurRadius = 48
    cursorGlow.shadowOffset = .zero
    cursorGlow.set()
    NSColor.white.withAlphaComponent(0.78).setFill()
    cursor.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    let cursorShadow = NSShadow()
    cursorShadow.shadowColor = color(0x181132, alpha: 0.38)
    cursorShadow.shadowBlurRadius = 28
    cursorShadow.shadowOffset = NSSize(width: 0, height: -12)
    cursorShadow.set()
    NSColor.white.setFill()
    cursor.fill()
    NSGraphicsContext.restoreGraphicsState()

    let cursorGradient = NSGradient(
        starting: color(0xFFFFFF),
        ending: color(0xDCE8FF)
    )!
    cursorGradient.draw(in: cursor, angle: 90)

    color(0xFFFFFF, alpha: 0.82).setStroke()
    cursor.lineWidth = 7
    cursor.stroke()

    let cursorShine = NSBezierPath()
    cursorShine.appendArc(
        withCenter: NSPoint(x: 512, y: 512),
        radius: 96,
        startAngle: 34,
        endAngle: 146
    )
    NSColor.white.withAlphaComponent(0.78).setStroke()
    cursorShine.lineWidth = 8
    cursorShine.lineCapStyle = .round
    cursorShine.stroke()

    let snapMarks = [
        (NSPoint(x: 346, y: 512), NSPoint(x: 370, y: 512)),
        (NSPoint(x: 654, y: 512), NSPoint(x: 678, y: 512))
    ]
    for (start, end) in snapMarks {
        let mark = NSBezierPath()
        mark.move(to: start)
        mark.line(to: end)
        mark.lineWidth = 10
        mark.lineCapStyle = .round
        color(0xD9FAFF, alpha: 0.68).setStroke()
        mark.stroke()
    }
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
