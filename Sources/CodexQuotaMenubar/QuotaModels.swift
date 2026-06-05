import Foundation
import SwiftUI

enum QuotaSource: String, CaseIterable, Identifiable, Sendable {
    case codexAuth = "Codex 登录态"
    case local = "本机状态"
    case manual = "手动填写"

    var id: String { rawValue }
}

enum DisplayMode: String, CaseIterable, Identifiable, Sendable {
    case ring = "圆环"
    case percentage = "百分比"

    var id: String { rawValue }
}

enum QuotaLevel: String, Sendable {
    case normal = "正常"
    case low = "额度偏低"
    case critical = "接近耗尽"
    case unknown = "未知"

    var color: Color {
        switch self {
        case .normal:
            return .quotaNormal
        case .low:
            return .quotaLow
        case .critical:
            return .quotaCritical
        case .unknown:
            return .secondary
        }
    }

    static func classify(percent: Int?, lowThreshold: Int) -> QuotaLevel {
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

extension Color {
    static let quotaNormal = Color(red: 0.18, green: 0.47, blue: 0.26)
    static let quotaLow = Color(red: 0.73, green: 0.43, blue: 0.10)
    static let quotaCritical = Color(red: 0.72, green: 0.16, blue: 0.14)
}

enum QuotaWindowKind: String, Sendable {
    case fiveHour = "5 小时额度"
    case weekly = "周额度"
}

struct QuotaWindowSnapshot: Sendable {
    var kind: QuotaWindowKind
    var percentRemaining: Int?
    var resetAt: Date?

    var isKnown: Bool {
        percentRemaining != nil
    }

    var percentUsed: Int? {
        percentRemaining.map { max(0, min(100, 100 - $0)) }
    }
}

struct QuotaSnapshot: Sendable {
    var fiveHour: QuotaWindowSnapshot
    var weekly: QuotaWindowSnapshot
    var source: QuotaSource
    var detail: String
    var capturedAt: Date
    var failed: Bool

    var percentRemaining: Int? {
        let values = [fiveHour.percentRemaining, weekly.percentRemaining].compactMap(\.self)
        return values.min()
    }

    var bottleneckRemainingPercent: Int? {
        percentRemaining
    }

    var bottleneckWindows: [QuotaWindowKind] {
        guard let percentRemaining else { return [] }
        return [fiveHour, weekly]
            .filter { $0.percentRemaining == percentRemaining }
            .map(\.kind)
    }

    var bottleneckText: String {
        switch bottleneckWindows {
        case []:
            return "未知"
        case [.fiveHour]:
            return QuotaWindowKind.fiveHour.rawValue
        case [.weekly]:
            return QuotaWindowKind.weekly.rawValue
        default:
            return "并列瓶颈"
        }
    }

    var resetAt: Date? {
        matchingBottleneckWindows.compactMap(\.resetAt).min()
    }

    var bottleneck: QuotaWindowKind? {
        let windows = bottleneckWindows
        return windows.count == 1 ? windows.first : nil
    }

    private var matchingBottleneckWindows: [QuotaWindowSnapshot] {
        guard let percentRemaining else { return [] }
        return [fiveHour, weekly].filter { $0.percentRemaining == percentRemaining }
    }

    static func unknown(source: QuotaSource, detail: String, failed: Bool = false) -> QuotaSnapshot {
        QuotaSnapshot(
            fiveHour: QuotaWindowSnapshot(kind: .fiveHour, percentRemaining: nil, resetAt: nil),
            weekly: QuotaWindowSnapshot(kind: .weekly, percentRemaining: nil, resetAt: nil),
            source: source,
            detail: detail,
            capturedAt: Date(),
            failed: failed
        )
    }

    static func singleWindow(
        percentRemaining: Int?,
        resetAt: Date?,
        source: QuotaSource,
        detail: String,
        capturedAt: Date = Date(),
        failed: Bool = false
    ) -> QuotaSnapshot {
        let normalizedPercent = percentRemaining.map { max(0, min(100, $0)) }
        return QuotaSnapshot(
            fiveHour: QuotaWindowSnapshot(kind: .fiveHour, percentRemaining: normalizedPercent, resetAt: resetAt),
            weekly: QuotaWindowSnapshot(kind: .weekly, percentRemaining: normalizedPercent, resetAt: resetAt),
            source: source,
            detail: detail,
            capturedAt: capturedAt,
            failed: failed
        )
    }
}
