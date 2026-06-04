import AppKit
import SwiftUI

enum MenuBarQuotaIcon {
    static func image(snapshot: QuotaSnapshot, lowThreshold: Int, isRefreshing: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size)
        image.isTemplate = false

        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        drawRing(
            in: NSRect(x: 2.5, y: 2.5, width: 17, height: 17),
            percent: snapshot.fiveHour.percentRemaining,
            level: level(for: snapshot.fiveHour.percentRemaining, lowThreshold: lowThreshold),
            lineWidth: 3.4,
            isRefreshing: isRefreshing
        )
        drawRing(
            in: NSRect(x: 7, y: 7, width: 8, height: 8),
            percent: snapshot.weekly.percentRemaining,
            level: level(for: snapshot.weekly.percentRemaining, lowThreshold: lowThreshold),
            lineWidth: 2.8,
            isRefreshing: isRefreshing
        )

        image.unlockFocus()
        return image
    }

    private static func drawRing(
        in rect: NSRect,
        percent: Int?,
        level: QuotaLevel,
        lineWidth: CGFloat,
        isRefreshing: Bool
    ) {
        let track = NSBezierPath(ovalIn: rect)
        track.lineWidth = lineWidth
        trackColor(for: level).setStroke()
        track.stroke()

        guard let percent else { return }

        let progress = max(0, min(100, percent))
        let startAngle: CGFloat = isRefreshing ? -40 : 90
        let endAngle = startAngle - CGFloat(progress) * 3.6
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        let path = NSBezierPath()
        path.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true
        )
        path.lineWidth = lineWidth
        path.lineCapStyle = .round

        strokeColor(for: level).setStroke()
        path.stroke()
    }

    private static func level(for percent: Int?, lowThreshold: Int) -> QuotaLevel {
        guard let percent else { return .unknown }
        if percent <= 5 {
            return .critical
        }
        if percent <= lowThreshold {
            return .low
        }
        return .normal
    }

    private static func strokeColor(for level: QuotaLevel) -> NSColor {
        switch level {
        case .normal:
            return NSColor(calibratedRed: 0.87, green: 0.96, blue: 0.88, alpha: 1)
        case .low:
            return NSColor(calibratedRed: 0.95, green: 0.70, blue: 0.28, alpha: 1)
        case .critical:
            return NSColor(calibratedRed: 0.96, green: 0.36, blue: 0.32, alpha: 1)
        case .unknown:
            return NSColor(calibratedWhite: 0.92, alpha: 0.78)
        }
    }

    private static func trackColor(for level: QuotaLevel) -> NSColor {
        switch level {
        case .unknown:
            return NSColor(calibratedWhite: 0.92, alpha: 0.32)
        default:
            return NSColor(calibratedWhite: 0.92, alpha: 0.22)
        }
    }
}
