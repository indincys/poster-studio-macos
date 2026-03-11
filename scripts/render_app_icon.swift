#!/usr/bin/env swift

import AppKit

func color(_ hex: Int, alpha: CGFloat = 1.0) -> NSColor {
    let red = CGFloat((hex >> 16) & 0xFF) / 255.0
    let green = CGFloat((hex >> 8) & 0xFF) / 255.0
    let blue = CGFloat(hex & 0xFF) / 255.0
    return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: render_app_icon.swift <output-png>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: NSString(string: CommandLine.arguments[1]).expandingTildeInPath)
let canvas = CGSize(width: 1024, height: 1024)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas.width),
    pixelsHigh: Int(canvas.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Failed to create bitmap context\n", stderr)
    exit(1)
}

bitmap.size = canvas

guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Failed to create graphics context\n", stderr)
    exit(1)
}

NSGraphicsContext.current = graphicsContext

let cgContext = graphicsContext.cgContext
cgContext.setAllowsAntialiasing(true)
cgContext.setShouldAntialias(true)
cgContext.interpolationQuality = .high
cgContext.translateBy(x: 0, y: canvas.height)
cgContext.scaleBy(x: 1, y: -1)

let backgroundRect = NSRect(x: 64, y: 64, width: 896, height: 896)
let backgroundPath = NSBezierPath(roundedRect: backgroundRect, xRadius: 224, yRadius: 224)
cgContext.saveGState()
backgroundPath.addClip()

NSGradient(colors: [
    color(0xFF6A3D),
    color(0xFF9742),
    color(0xFFC84A),
])?.draw(in: backgroundPath, angle: -42)

cgContext.restoreGState()

color(0xFFF1D7, alpha: 0.18).setFill()
NSBezierPath(ovalIn: NSRect(x: 674, y: 68, width: 292, height: 292)).fill()

let shadowPath = NSBezierPath()
shadowPath.move(to: NSPoint(x: 188, y: 798))
shadowPath.curve(to: NSPoint(x: 734, y: 760), controlPoint1: NSPoint(x: 308, y: 720), controlPoint2: NSPoint(x: 502, y: 704))
shadowPath.curve(to: NSPoint(x: 960, y: 960), controlPoint1: NSPoint(x: 832, y: 784), controlPoint2: NSPoint(x: 906, y: 844))
shadowPath.line(to: NSPoint(x: 242, y: 960))
shadowPath.curve(to: NSPoint(x: 188, y: 798), controlPoint1: NSPoint(x: 184, y: 922), controlPoint2: NSPoint(x: 158, y: 850))
shadowPath.close()
color(0xAF2B1D, alpha: 0.34).setFill()
shadowPath.fill()

cgContext.saveGState()
let rotate = NSAffineTransform()
rotate.translateX(by: 512, yBy: 512)
rotate.rotate(byDegrees: -11)
rotate.translateX(by: -512, yBy: -512)
rotate.concat()

color(0x1A1715).setFill()
NSBezierPath(roundedRect: NSRect(x: 256, y: 212, width: 528, height: 600), xRadius: 136, yRadius: 136).fill()

let foldPath = NSBezierPath()
foldPath.move(to: NSPoint(x: 644, y: 212))
foldPath.line(to: NSPoint(x: 710, y: 212))
foldPath.curve(to: NSPoint(x: 784, y: 286), controlPoint1: NSPoint(x: 750, y: 212), controlPoint2: NSPoint(x: 784, y: 246))
foldPath.line(to: NSPoint(x: 784, y: 354))
foldPath.close()
color(0xFF6A3D).setFill()
foldPath.fill()

let glowVerticalPath = NSBezierPath(roundedRect: NSRect(x: 324, y: 282, width: 136, height: 460), xRadius: 68, yRadius: 68)
cgContext.saveGState()
glowVerticalPath.addClip()
NSGradient(colors: [
    color(0xFFF7EA, alpha: 0.98),
    color(0xFFE6C1, alpha: 0.92),
])?.draw(in: glowVerticalPath, angle: 90)
cgContext.restoreGState()

let glowTopPath = NSBezierPath(roundedRect: NSRect(x: 438, y: 282, width: 272, height: 264), xRadius: 132, yRadius: 132)
cgContext.saveGState()
glowTopPath.addClip()
NSGradient(colors: [
    color(0xFFF7EA, alpha: 0.98),
    color(0xFFE6C1, alpha: 0.92),
])?.draw(in: glowTopPath, angle: 90)
cgContext.restoreGState()

color(0x1A1715).setFill()
NSBezierPath(ovalIn: NSRect(x: 488, y: 328, width: 172, height: 172)).fill()

let playPath = NSBezierPath()
playPath.move(to: NSPoint(x: 546, y: 356))
playPath.line(to: NSPoint(x: 650, y: 414))
playPath.line(to: NSPoint(x: 546, y: 472))
playPath.close()
color(0xFF6A3D).setFill()
playPath.fill()

cgContext.restoreGState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Failed to create PNG data\n", stderr)
    exit(1)
}

do {
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
    try pngData.write(to: outputURL)
} catch {
    fputs("Failed to write PNG: \(error)\n", stderr)
    exit(1)
}
