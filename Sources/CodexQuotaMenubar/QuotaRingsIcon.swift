import SwiftUI

struct QuotaRingsIcon: View {
    let snapshot: QuotaSnapshot
    let lowThreshold: Int
    let isRefreshing: Bool
    var style: QuotaRingsIconStyle = .panel

    var body: some View {
        if isRefreshing {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                rings
                    .rotationEffect(.degrees(rotationAngle(at: timeline.date)))
            }
        } else {
            rings
        }
    }

    private var rings: some View {
        ZStack {
            RingView(
                percent: snapshot.fiveHour.percentRemaining,
                level: level(for: snapshot.fiveHour.percentRemaining),
                lineWidth: style.outerLineWidth,
                style: style
            )
            .frame(width: style.outerSize, height: style.outerSize)

            RingView(
                percent: snapshot.weekly.percentRemaining,
                level: level(for: snapshot.weekly.percentRemaining),
                lineWidth: style.innerLineWidth,
                style: style
            )
            .frame(width: style.innerSize, height: style.innerSize)

        }
        .frame(width: style.canvasSize, height: style.canvasSize)
        .drawingGroup(opaque: false)
    }

    private func rotationAngle(at date: Date) -> Double {
        let duration = 1.1
        let progress = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration) / duration
        return progress * 360
    }

    private func level(for percent: Int?) -> QuotaLevel {
        guard let percent else { return .unknown }
        if percent <= 5 {
            return .critical
        }
        if percent <= lowThreshold {
            return .low
        }
        return .normal
    }
}

enum QuotaRingsIconStyle {
    case menuBar
    case panel

    var canvasSize: CGFloat {
        switch self {
        case .menuBar:
            return 21
        case .panel:
            return 24
        }
    }

    var outerSize: CGFloat {
        switch self {
        case .menuBar:
            return 19
        case .panel:
            return 22
        }
    }

    var innerSize: CGFloat {
        switch self {
        case .menuBar:
            return 11
        case .panel:
            return 13
        }
    }

    var outerLineWidth: CGFloat {
        switch self {
        case .menuBar:
            return 3.8
        case .panel:
            return 3.2
        }
    }

    var innerLineWidth: CGFloat {
        switch self {
        case .menuBar:
            return 3.2
        case .panel:
            return 2.8
        }
    }

    func foregroundColor(for level: QuotaLevel) -> Color {
        switch self {
        case .menuBar:
            switch level {
            case .normal:
                return Color.white.opacity(0.94)
            case .low:
                return Color(red: 0.95, green: 0.68, blue: 0.28)
            case .critical:
                return Color(red: 0.95, green: 0.34, blue: 0.30)
            case .unknown:
                return Color.white.opacity(0.64)
            }
        case .panel:
            return level.color
        }
    }

    func trackColor(for level: QuotaLevel) -> Color {
        switch self {
        case .menuBar:
            return Color.white.opacity(level == .unknown ? 0.28 : 0.20)
        case .panel:
            return level.color.opacity(level == .unknown ? 0.18 : 0.14)
        }
    }
}

private struct RingView: View {
    let percent: Int?
    let level: QuotaLevel
    let lineWidth: CGFloat
    let style: QuotaRingsIconStyle

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(style.trackColor(for: level), lineWidth: lineWidth)

            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: progress)
                .stroke(
                    style.foregroundColor(for: level),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .opacity(percent == nil ? 0.35 : 1)
        }
    }

    private var progress: CGFloat {
        guard let percent else { return 0 }
        return CGFloat(max(0, min(100, percent))) / 100
    }
}
