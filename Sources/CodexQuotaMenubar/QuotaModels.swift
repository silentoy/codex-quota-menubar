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

enum BottleneckMode: String, CaseIterable, Identifiable, Sendable {
    case percentage = "按剩余百分比"
    case smart = "按使用趋势"

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

struct QuotaHistoryRecord: Codable, Sendable {
    var fiveHourPercentRemaining: Int?
    var weeklyPercentRemaining: Int?
    var capturedAt: Date

    func percentRemaining(for kind: QuotaWindowKind) -> Int? {
        switch kind {
        case .fiveHour:
            return fiveHourPercentRemaining
        case .weekly:
            return weeklyPercentRemaining
        }
    }
}

struct QuotaBottleneckEvaluation: Sendable {
    var windows: [QuotaWindowKind]
    var remainingPercent: Int?
    var resetAt: Date?
    var text: String
    var explanation: String
}

enum QuotaBottleneckEvaluator {
    static func evaluate(
        snapshot: QuotaSnapshot,
        historyRecords: [QuotaHistoryRecord],
        mode: BottleneckMode,
        now: Date = Date()
    ) -> QuotaBottleneckEvaluation {
        switch mode {
        case .percentage:
            return percentageEvaluation(for: snapshot)
        case .smart:
            return smartEvaluation(for: snapshot, historyRecords: historyRecords, now: now)
        }
    }

    static func calculateBurnRate(
        windowKind: QuotaWindowKind,
        snapshot: QuotaSnapshot,
        historyRecords: [QuotaHistoryRecord],
        duration: TimeInterval,
        now: Date = Date()
    ) -> Double {
        let cutoff = now.addingTimeInterval(-duration)
        var records = historyRecords
            .filter { $0.capturedAt >= cutoff && $0.capturedAt <= now }
            .map { (capturedAt: $0.capturedAt, percent: $0.percentRemaining(for: windowKind)) }

        let currentPercent: Int?
        switch windowKind {
        case .fiveHour:
            currentPercent = snapshot.fiveHour.percentRemaining
        case .weekly:
            currentPercent = snapshot.weekly.percentRemaining
        }
        records.append((snapshot.capturedAt, currentPercent))
        records = records
            .filter { $0.percent != nil }
            .sorted { $0.capturedAt < $1.capturedAt }

        guard records.count >= 2 else { return 0 }

        var consumedPercent = 0.0
        var consumedHours = 0.0

        for index in 1..<records.count {
            guard let previous = records[index - 1].percent,
                  let current = records[index].percent else {
                continue
            }
            let elapsed = records[index].capturedAt.timeIntervalSince(records[index - 1].capturedAt)
            guard elapsed > 0, current < previous else { continue }

            consumedPercent += Double(previous - current)
            consumedHours += elapsed / 3600
        }

        guard consumedHours > 0 else { return 0 }
        return consumedPercent / consumedHours
    }

    private static func percentageEvaluation(for snapshot: QuotaSnapshot) -> QuotaBottleneckEvaluation {
        let windows = snapshot.bottleneckWindows
        let percent = snapshot.bottleneckRemainingPercent
        let text = snapshot.bottleneckText
        let explanation: String
        if let percent {
            explanation = "当前按剩余额度百分比判断瓶颈，剩余百分比最低的窗口会被标记为瓶颈。\(text) 当前剩余 \(percent)% 。"
        } else {
            explanation = "当前按剩余额度百分比判断瓶颈，但暂未读取到精确额度。"
        }

        return QuotaBottleneckEvaluation(
            windows: windows,
            remainingPercent: percent,
            resetAt: snapshot.resetAt,
            text: text,
            explanation: explanation
        )
    }

    private static func smartEvaluation(
        for snapshot: QuotaSnapshot,
        historyRecords: [QuotaHistoryRecord],
        now: Date
    ) -> QuotaBottleneckEvaluation {
        let knownWindows = [snapshot.fiveHour, snapshot.weekly].filter { $0.percentRemaining != nil }
        guard !knownWindows.isEmpty else {
            return QuotaBottleneckEvaluation(
                windows: [],
                remainingPercent: nil,
                resetAt: nil,
                text: "未知",
                explanation: "当前按使用趋势判断瓶颈，但暂未读取到精确额度。"
            )
        }

        let scores = knownWindows.map { window in
            score(for: window, snapshot: snapshot, historyRecords: historyRecords, now: now)
        }

        let deficitScores = scores.filter { $0.deficitHours > 0 }
        if let maxDeficit = deficitScores.map(\.deficitHours).max() {
            let winners = deficitScores.filter { abs($0.deficitHours - maxDeficit) < 0.0001 }
            return result(from: winners, reason: .deficit)
        }

        if let maxSupport = scores.map(\.supportScore).max() {
            let winners = scores.filter { abs($0.supportScore - maxSupport) < 0.0001 }
            return result(from: winners, reason: .support)
        }

        return percentageEvaluation(for: snapshot)
    }

    private static func score(
        for window: QuotaWindowSnapshot,
        snapshot: QuotaSnapshot,
        historyRecords: [QuotaHistoryRecord],
        now: Date
    ) -> WindowScore {
        let percent = window.percentRemaining ?? 0
        let remainingHours = max(0, window.resetAt?.timeIntervalSince(now) ?? 0) / 3600
        let duration: TimeInterval = window.kind == .fiveHour ? 3 * 3600 : 24 * 3600
        let burnRate = calculateBurnRate(
            windowKind: window.kind,
            snapshot: snapshot,
            historyRecords: historyRecords,
            duration: duration,
            now: now
        )

        let timeToDrainHours = burnRate > 0 ? Double(percent) / burnRate : nil
        let deficitHours = timeToDrainHours.map { max(0, remainingHours - $0) } ?? 0
        let supportScore = remainingHours / max(0.5, Double(percent))

        return WindowScore(
            window: window,
            burnRate: burnRate,
            resetHours: remainingHours,
            timeToDrainHours: timeToDrainHours,
            deficitHours: deficitHours,
            supportScore: supportScore
        )
    }

    private static func result(from scores: [WindowScore], reason: SmartReason) -> QuotaBottleneckEvaluation {
        let windows = scores.map { $0.window.kind }
        let text = text(for: windows)
        let percent = scores.compactMap { $0.window.percentRemaining }.min()
        let resetAt = scores.compactMap { $0.window.resetAt }.min()
        let first = scores[0]
        let explanation: String

        switch reason {
        case .deficit:
            let ttdText = first.timeToDrainHours.map { formatHours($0) } ?? "未知"
            explanation = "\(text) 是当前使用趋势下的主要限制：按最近消耗速度预计 \(ttdText) 后用尽，早于重置时间。"
        case .support:
            explanation = "\(text) 重置时间较长（每 1% 需支撑 \(formatHours(first.supportScore))），是当前使用的主要限制。"
        }

        return QuotaBottleneckEvaluation(
            windows: windows,
            remainingPercent: percent,
            resetAt: resetAt,
            text: text,
            explanation: explanation
        )
    }

    private static func text(for windows: [QuotaWindowKind]) -> String {
        switch windows {
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

    private static func formatHours(_ hours: Double) -> String {
        if hours < 1 {
            return "\(max(1, Int((hours * 60).rounded()))) 分钟"
        }
        if hours < 24 {
            let rounded = (hours * 10).rounded() / 10
            return "\(rounded) 小时"
        }
        let days = (hours / 24 * 10).rounded() / 10
        return "\(days) 天"
    }

    private struct WindowScore {
        var window: QuotaWindowSnapshot
        var burnRate: Double
        var resetHours: Double
        var timeToDrainHours: Double?
        var deficitHours: Double
        var supportScore: Double
    }

    private enum SmartReason {
        case deficit
        case support
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
