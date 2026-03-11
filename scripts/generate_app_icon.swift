import AppKit
import Darwin
import Foundation

private let iconSpecs: [(name: String, size: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

struct AppIconGenerator {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else {
            fputs("Usage: swift generate_app_icon.swift <iconset_dir> [preview_png]\n", stderr)
            exit(1)
        }

        let iconsetURL = URL(fileURLWithPath: arguments[1], isDirectory: true)
        let previewURL = arguments.count >= 3 ? URL(fileURLWithPath: arguments[2]) : nil
        let fileManager = FileManager.default

        try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true, attributes: nil)

        var previewData: Data?
        for spec in iconSpecs {
            let image = drawIcon(side: spec.size)
            let fileURL = iconsetURL.appendingPathComponent(spec.name)
            let pngData = try pngData(for: image)
            try pngData.write(to: fileURL)
            if spec.size == 1024 {
                previewData = pngData
            }
        }

        if let previewURL, let previewData {
            try fileManager.createDirectory(at: previewURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            try previewData.write(to: previewURL)
        }
    }

    private static func pngData(for image: NSImage) throws -> Data {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw NSError(domain: "AppIconGenerator", code: 1, userInfo: nil)
        }
        return png
    }

    private static func drawIcon(side: CGFloat) -> NSImage {
        let size = NSSize(width: side, height: side)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        guard let context = NSGraphicsContext.current?.cgContext else {
            return image
        }

        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        let canvas = NSRect(origin: .zero, size: size)
        let cornerRadius = side * 0.23
        let backgroundPath = NSBezierPath(roundedRect: canvas, xRadius: cornerRadius, yRadius: cornerRadius)

        NSGraphicsContext.saveGraphicsState()
        backgroundPath.addClip()

        NSGradient(
            colors: [
                NSColor(hex: 0xF6FCFF),
                NSColor(hex: 0xD9F2FF),
                NSColor(hex: 0x73BEEF),
            ]
        )?.draw(in: backgroundPath, angle: -38)

        NSColor.white.withAlphaComponent(0.54).setFill()
        NSBezierPath(ovalIn: NSRect(x: -side * 0.10, y: side * 0.72, width: side * 0.58, height: side * 0.26)).fill()

        NSColor(hex: 0x2C85CE, alpha: 0.18).setFill()
        NSBezierPath(ovalIn: NSRect(x: side * 0.48, y: side * 0.06, width: side * 0.58, height: side * 0.40)).fill()

        let wavePath = NSBezierPath()
        wavePath.move(to: NSPoint(x: -side * 0.08, y: side * 0.18))
        wavePath.curve(
            to: NSPoint(x: side * 0.36, y: side * 0.28),
            controlPoint1: NSPoint(x: side * 0.06, y: side * 0.12),
            controlPoint2: NSPoint(x: side * 0.20, y: side * 0.32)
        )
        wavePath.curve(
            to: NSPoint(x: side * 1.04, y: side * 0.12),
            controlPoint1: NSPoint(x: side * 0.58, y: side * 0.25),
            controlPoint2: NSPoint(x: side * 0.82, y: side * 0.06)
        )
        wavePath.line(to: NSPoint(x: side * 1.04, y: -side * 0.08))
        wavePath.line(to: NSPoint(x: -side * 0.08, y: -side * 0.08))
        wavePath.close()
        NSColor(hex: 0x5AAEEB, alpha: 0.20).setFill()
        wavePath.fill()

        let ringPath = NSBezierPath(roundedRect: canvas.insetBy(dx: side * 0.04, dy: side * 0.04), xRadius: side * 0.18, yRadius: side * 0.18)
        ringPath.lineWidth = max(1, side * 0.014)
        NSColor.white.withAlphaComponent(0.28).setStroke()
        ringPath.stroke()
        NSGraphicsContext.restoreGraphicsState()

        let backCardRect = NSRect(x: side * 0.34, y: side * 0.31, width: side * 0.34, height: side * 0.42)
        let backCardPath = NSBezierPath(roundedRect: backCardRect, xRadius: side * 0.08, yRadius: side * 0.08)
        NSColor(hex: 0xE7F6FF, alpha: 0.55).setFill()
        backCardPath.fill()
        backCardPath.lineWidth = max(1, side * 0.008)
        NSColor(hex: 0x76B6E7, alpha: 0.28).setStroke()
        backCardPath.stroke()

        let cardRect = NSRect(x: side * 0.18, y: side * 0.16, width: side * 0.50, height: side * 0.62)
        let cardRadius = side * 0.10

        NSGraphicsContext.saveGraphicsState()
        let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: cardRadius, yRadius: cardRadius)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(hex: 0x387FBB, alpha: 0.18)
        shadow.shadowBlurRadius = side * 0.09
        shadow.shadowOffset = NSSize(width: 0, height: -side * 0.025)
        shadow.set()
        NSColor.white.withAlphaComponent(0.94).setFill()
        cardPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        let cardStrokePath = NSBezierPath(roundedRect: cardRect, xRadius: cardRadius, yRadius: cardRadius)
        cardStrokePath.lineWidth = max(1, side * 0.01)
        NSColor(hex: 0x8FC5EE, alpha: 0.55).setStroke()
        cardStrokePath.stroke()

        let topStripRect = NSRect(
            x: cardRect.minX + cardRect.width * 0.10,
            y: cardRect.maxY - cardRect.height * 0.16,
            width: cardRect.width * 0.38,
            height: cardRect.height * 0.055
        )
        let topStripPath = NSBezierPath(roundedRect: topStripRect, xRadius: topStripRect.height / 2, yRadius: topStripRect.height / 2)
        NSColor(hex: 0xCAE8FF).setFill()
        topStripPath.fill()

        let stemRect = NSRect(
            x: cardRect.minX + cardRect.width * 0.18,
            y: cardRect.minY + cardRect.height * 0.22,
            width: cardRect.width * 0.18,
            height: cardRect.height * 0.48
        )
        let stemPath = NSBezierPath(roundedRect: stemRect, xRadius: stemRect.width * 0.48, yRadius: stemRect.width * 0.48)
        NSGradient(colors: [NSColor(hex: 0x5DBDF6), NSColor(hex: 0x2B92E6)])?.draw(in: stemPath, angle: -90)

        let playDiameter = cardRect.width * 0.36
        let playRect = NSRect(
            x: stemRect.maxX - stemRect.width * 0.12,
            y: cardRect.minY + cardRect.height * 0.46,
            width: playDiameter,
            height: playDiameter
        )
        let playPath = NSBezierPath(ovalIn: playRect)
        NSGradient(colors: [NSColor(hex: 0x74D0FF), NSColor(hex: 0x379BEA)])?.draw(in: playPath, angle: -65)

        let triangle = NSBezierPath()
        triangle.move(to: NSPoint(x: playRect.minX + playRect.width * 0.41, y: playRect.minY + playRect.height * 0.31))
        triangle.line(to: NSPoint(x: playRect.minX + playRect.width * 0.71, y: playRect.midY))
        triangle.line(to: NSPoint(x: playRect.minX + playRect.width * 0.41, y: playRect.minY + playRect.height * 0.69))
        triangle.close()
        NSColor.white.setFill()
        triangle.fill()

        let firstLineRect = NSRect(x: cardRect.minX + cardRect.width * 0.18, y: cardRect.minY + cardRect.height * 0.14, width: cardRect.width * 0.42, height: cardRect.height * 0.075)
        let secondLineRect = NSRect(x: cardRect.minX + cardRect.width * 0.18, y: cardRect.minY + cardRect.height * 0.24, width: cardRect.width * 0.26, height: cardRect.height * 0.075)
        let thirdLineRect = NSRect(x: cardRect.minX + cardRect.width * 0.50, y: cardRect.minY + cardRect.height * 0.24, width: cardRect.width * 0.12, height: cardRect.height * 0.075)

        for (rect, color) in [
            (firstLineRect, NSColor(hex: 0xA8D9FA)),
            (secondLineRect, NSColor(hex: 0xCDEBFF)),
            (thirdLineRect, NSColor(hex: 0x69C3F7)),
        ] {
            let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
            color.withAlphaComponent(0.92).setFill()
            path.fill()
        }

        let chipRect = NSRect(
            x: cardRect.maxX - cardRect.width * 0.22,
            y: cardRect.minY + cardRect.height * 0.14,
            width: cardRect.width * 0.14,
            height: cardRect.height * 0.12
        )
        let chipPath = NSBezierPath(roundedRect: chipRect, xRadius: chipRect.height * 0.42, yRadius: chipRect.height * 0.42)
        NSGradient(colors: [NSColor(hex: 0x76CBF8), NSColor(hex: 0x49A9ED)])?.draw(in: chipPath, angle: -40)

        NSGraphicsContext.restoreGraphicsState()

        let sparkleCenter = NSPoint(x: side * 0.74, y: side * 0.76)
        let sparklePath = sparkle(at: sparkleCenter, outerRadius: side * 0.060, innerRadius: side * 0.022)
        NSColor.white.withAlphaComponent(0.96).setFill()
        sparklePath.fill()

        let miniSparklePath = sparkle(at: NSPoint(x: side * 0.82, y: side * 0.67), outerRadius: side * 0.026, innerRadius: side * 0.010)
        NSColor(hex: 0xDCF4FF, alpha: 0.98).setFill()
        miniSparklePath.fill()

        return image
    }

    private static func sparkle(at center: NSPoint, outerRadius: CGFloat, innerRadius: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let points = 8

        for index in 0..<(points * 2) {
            let angle = CGFloat(index) * .pi / CGFloat(points) - (.pi / 2)
            let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
            let point = NSPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )

            if index == 0 {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
        }

        path.close()
        return path
    }
}

try AppIconGenerator.main()

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
