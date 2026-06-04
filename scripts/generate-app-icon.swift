import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "dist/AppIcon.icns"
let outputURL = URL(fileURLWithPath: outputPath)
let fileManager = FileManager.default
let iconsetURL = outputURL.deletingPathExtension().appendingPathExtension("iconset")

try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

let sizes: [(name: String, pixels: Int)] = [
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

for size in sizes {
    let image = drawIcon(size: CGFloat(size.pixels))
    let url = iconsetURL.appendingPathComponent(size.name)
    try writePNG(image, to: url)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "GenerateAppIcon", code: Int(process.terminationStatus))
}

try? fileManager.removeItem(at: iconsetURL)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()

    let inset = max(1, size * 0.035)
    let radius = size * 0.23
    let background = NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), xRadius: radius, yRadius: radius)
    NSColor(calibratedRed: 0.06, green: 0.20, blue: 0.12, alpha: 1).setFill()
    background.fill()

    let innerGlow = NSBezierPath(ovalIn: rect.insetBy(dx: size * 0.18, dy: size * 0.18))
    NSColor(calibratedRed: 0.18, green: 0.42, blue: 0.24, alpha: 0.46).setFill()
    innerGlow.fill()

    let centerDot = NSBezierPath(ovalIn: rect.insetBy(dx: size * 0.405, dy: size * 0.405))
    NSColor(calibratedRed: 0.82, green: 0.94, blue: 0.82, alpha: 0.96).setFill()
    centerDot.fill()

    drawRing(
        rect: rect.insetBy(dx: size * 0.22, dy: size * 0.22),
        progress: 0.65,
        lineWidth: max(2, size * 0.082),
        stroke: NSColor(calibratedRed: 0.84, green: 0.98, blue: 0.83, alpha: 1),
        track: NSColor(calibratedWhite: 1, alpha: 0.26)
    )
    drawRing(
        rect: rect.insetBy(dx: size * 0.34, dy: size * 0.34),
        progress: 0.32,
        lineWidth: max(1.5, size * 0.064),
        stroke: NSColor(calibratedRed: 0.98, green: 0.73, blue: 0.28, alpha: 1),
        track: NSColor(calibratedWhite: 1, alpha: 0.28)
    )

    image.unlockFocus()
    return image
}

func drawRing(rect: NSRect, progress: CGFloat, lineWidth: CGFloat, stroke: NSColor, track: NSColor) {
    let trackPath = NSBezierPath(ovalIn: rect)
    trackPath.lineWidth = lineWidth
    track.setStroke()
    trackPath.stroke()

    let center = NSPoint(x: rect.midX, y: rect.midY)
    let radius = min(rect.width, rect.height) / 2
    let path = NSBezierPath()
    path.appendArc(
        withCenter: center,
        radius: radius,
        startAngle: 90,
        endAngle: 90 - progress * 360,
        clockwise: true
    )
    path.lineCapStyle = .round
    path.lineWidth = lineWidth
    stroke.setStroke()
    path.stroke()
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "GenerateAppIcon", code: 1)
    }
    try png.write(to: url)
}
