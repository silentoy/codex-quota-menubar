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

enum QuotaUsageDayType: String, Codable, Sendable {
    case weekday
    case weekend

    static func classify(weekday: Int) -> QuotaUsageDayType {
        weekday == 1 || weekday == 7 ? .weekend : .weekday
    }
}

struct QuotaUsageHourBucket: Codable, Sendable {
    var dayKey: String
    var dayType: QuotaUsageDayType
    var weekday: Int
    var hour: Int
    var successRefreshCount: Int
    var activeRefreshCount: Int
    var fiveHourConsumedPercent: Double
    var weeklyConsumedPercent: Double

    func consumedPercent(for kind: QuotaWindowKind) -> Double {
        switch kind {
        case .fiveHour:
            return fiveHourConsumedPercent
        case .weekly:
            return weeklyConsumedPercent
        }
    }
}

struct QuotaUsageLastSample: Codable, Sendable {
    var capturedAt: Date
    var fiveHourPercentRemaining: Int?
    var weeklyPercentRemaining: Int?
    var fiveHourResetAt: Date?
    var weeklyResetAt: Date?

    func percentRemaining(for kind: QuotaWindowKind) -> Int? {
        switch kind {
        case .fiveHour:
            return fiveHourPercentRemaining
        case .weekly:
            return weeklyPercentRemaining
        }
    }
}

struct QuotaUsagePrediction: Sendable {
    var predictedConsumption: Double
    var matchedHourCount: Int
    var fallbackHourCount: Int
    var consideredHourCount: Int
    var matchDescription: String
}

enum QuotaUsageFrequencyRecorder {
    static let retentionDays = 30

    static func record(
        snapshot: QuotaSnapshot,
        buckets: inout [QuotaUsageHourBucket],
        lastSample: inout QuotaUsageLastSample?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        guard !snapshot.failed,
              snapshot.fiveHour.percentRemaining != nil || snapshot.weekly.percentRemaining != nil else {
            return
        }

        let date = snapshot.capturedAt
        let bucketIndex = index(for: date, in: buckets, calendar: calendar)
        if let bucketIndex {
            buckets[bucketIndex].successRefreshCount += 1
        } else {
            buckets.append(newBucket(for: date, calendar: calendar))
        }

        let currentIndex = index(for: date, in: buckets, calendar: calendar)!
        var fiveHourDrop = 0.0
        var weeklyDrop = 0.0

        if let lastSample {
            fiveHourDrop = drop(from: lastSample.fiveHourPercentRemaining, to: snapshot.fiveHour.percentRemaining)
            weeklyDrop = drop(from: lastSample.weeklyPercentRemaining, to: snapshot.weekly.percentRemaining)
        }

        if fiveHourDrop > 0 || weeklyDrop > 0 {
            buckets[currentIndex].activeRefreshCount += 1
            buckets[currentIndex].fiveHourConsumedPercent += fiveHourDrop
            buckets[currentIndex].weeklyConsumedPercent += weeklyDrop
        }

        lastSample = QuotaUsageLastSample(
            capturedAt: snapshot.capturedAt,
            fiveHourPercentRemaining: snapshot.fiveHour.percentRemaining,
            weeklyPercentRemaining: snapshot.weekly.percentRemaining,
            fiveHourResetAt: snapshot.fiveHour.resetAt,
            weeklyResetAt: snapshot.weekly.resetAt
        )

        prune(&buckets, now: now, calendar: calendar)
    }

    static func prune(
        _ buckets: inout [QuotaUsageHourBucket],
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        guard let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: now) else { return }
        let cutoffKey = dayKey(for: cutoff, calendar: calendar)
        buckets = buckets
            .filter { $0.dayKey >= cutoffKey }
            .sorted { lhs, rhs in
                lhs.dayKey == rhs.dayKey ? lhs.hour < rhs.hour : lhs.dayKey < rhs.dayKey
            }
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func index(
        for date: Date,
        in buckets: [QuotaUsageHourBucket],
        calendar: Calendar
    ) -> Int? {
        let key = dayKey(for: date, calendar: calendar)
        let hour = calendar.component(.hour, from: date)
        return buckets.firstIndex { $0.dayKey == key && $0.hour == hour }
    }

    private static func newBucket(for date: Date, calendar: Calendar) -> QuotaUsageHourBucket {
        let weekday = calendar.component(.weekday, from: date)
        return QuotaUsageHourBucket(
            dayKey: dayKey(for: date, calendar: calendar),
            dayType: QuotaUsageDayType.classify(weekday: weekday),
            weekday: weekday,
            hour: calendar.component(.hour, from: date),
            successRefreshCount: 1,
            activeRefreshCount: 0,
            fiveHourConsumedPercent: 0,
            weeklyConsumedPercent: 0
        )
    }

    private static func drop(from previous: Int?, to current: Int?) -> Double {
        guard let previous, let current, current < previous else { return 0 }
        return Double(previous - current)
    }
}

enum QuotaUsageFrequencyPredictor {
    static func predict(
        windowKind: QuotaWindowKind,
        from start: Date,
        resetAt: Date?,
        buckets: [QuotaUsageHourBucket],
        calendar: Calendar = .current
    ) -> QuotaUsagePrediction {
        guard let resetAt, resetAt > start, !buckets.isEmpty else {
            return QuotaUsagePrediction(
                predictedConsumption: 0,
                matchedHourCount: 0,
                fallbackHourCount: 0,
                consideredHourCount: 0,
                matchDescription: "历史不足"
            )
        }

        var predicted = 0.0
        var matched = 0
        var fallback = 0
        var considered = 0
        var cursor = calendar.dateInterval(of: .hour, for: start)?.start ?? start

        while cursor < resetAt {
            let hourEnd = calendar.date(byAdding: .hour, value: 1, to: cursor) ?? cursor.addingTimeInterval(3600)
            let overlapStart = max(start, cursor)
            let overlapEnd = min(resetAt, hourEnd)
            let fraction = max(0, overlapEnd.timeIntervalSince(overlapStart) / 3600)

            if fraction > 0 {
                considered += 1
                let weekday = calendar.component(.weekday, from: cursor)
                let dayType = QuotaUsageDayType.classify(weekday: weekday)
                let hour = calendar.component(.hour, from: cursor)
                let sameType = buckets.filter { $0.dayType == dayType && $0.hour == hour }
                let source: [QuotaUsageHourBucket]
                if sameType.isEmpty {
                    source = buckets.filter { $0.hour == hour }
                    if !source.isEmpty { fallback += 1 }
                } else {
                    source = sameType
                    matched += 1
                }

                if !source.isEmpty {
                    let average = source.map { $0.consumedPercent(for: windowKind) }.reduce(0, +) / Double(source.count)
                    predicted += average * fraction
                }
            }

            cursor = hourEnd
        }

        let description: String
        if matched > 0 {
            description = "周中/周末同小时"
        } else if fallback > 0 {
            description = "相同小时"
        } else {
            description = "历史不足"
        }

        return QuotaUsagePrediction(
            predictedConsumption: predicted,
            matchedHourCount: matched,
            fallbackHourCount: fallback,
            consideredHourCount: considered,
            matchDescription: description
        )
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
        usageBuckets: [QuotaUsageHourBucket] = [],
        mode: BottleneckMode,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> QuotaBottleneckEvaluation {
        switch mode {
        case .percentage:
            return percentageEvaluation(for: snapshot)
        case .smart:
            return smartEvaluation(
                for: snapshot,
                historyRecords: historyRecords,
                usageBuckets: usageBuckets,
                now: now,
                calendar: calendar
            )
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

        let durationHours = duration / 3600
        var weightedPercent = 0.0
        var weightedHours = 0.0

        for index in 1..<records.count {
            guard let previous = records[index - 1].percent,
                  let current = records[index].percent else {
                continue
            }
            let elapsed = records[index].capturedAt.timeIntervalSince(records[index - 1].capturedAt)
            guard elapsed > 0, current < previous else { continue }

            let midpoint = records[index - 1].capturedAt.addingTimeInterval(elapsed / 2)
            let dt = now.timeIntervalSince(midpoint) / 3600
            let weight = max(0.01, 1.0 - dt / durationHours)
            weightedPercent += weight * Double(previous - current)
            weightedHours += weight * (elapsed / 3600)
        }

        guard weightedHours > 0 else { return 0 }
        return weightedPercent / weightedHours
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
        usageBuckets: [QuotaUsageHourBucket],
        now: Date,
        calendar: Calendar
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

        if let usageEvaluation = usageFrequencyEvaluation(
            for: knownWindows,
            buckets: usageBuckets,
            now: now,
            calendar: calendar
        ) {
            return usageEvaluation
        }

        let scores = knownWindows.map { window in
            score(for: window, snapshot: snapshot, historyRecords: historyRecords, now: now)
        }

        let deficitScores = scores.filter { $0.deficitHours > 0 }
        if let minTTD = deficitScores.compactMap(\.timeToDrainHours).min() {
            let winners = deficitScores.filter {
                $0.timeToDrainHours.map { abs($0 - minTTD) < 0.0001 } ?? false
            }
            return result(from: winners, reason: .deficit)
        }

        if let maxSupport = scores.map(\.supportScore).max() {
            let winners = scores.filter { abs($0.supportScore - maxSupport) < 0.0001 }
            return result(from: winners, reason: .support)
        }

        return percentageEvaluation(for: snapshot)
    }

    private static func usageFrequencyEvaluation(
        for windows: [QuotaWindowSnapshot],
        buckets: [QuotaUsageHourBucket],
        now: Date,
        calendar: Calendar
    ) -> QuotaBottleneckEvaluation? {
        guard !buckets.isEmpty else { return nil }

        let risks = windows.compactMap { window -> UsageRisk? in
            guard let percent = window.percentRemaining else { return nil }
            let prediction = QuotaUsageFrequencyPredictor.predict(
                windowKind: window.kind,
                from: now,
                resetAt: window.resetAt,
                buckets: buckets,
                calendar: calendar
            )
            guard prediction.predictedConsumption > Double(percent) else { return nil }
            let baseRiskRatio = prediction.predictedConsumption / max(0.5, Double(percent))
            return UsageRisk(
                window: window,
                prediction: prediction,
                riskRatio: window.kind == .fiveHour ? baseRiskRatio * 1.5 : baseRiskRatio
            )
        }

        guard !risks.isEmpty,
              let maxRisk = risks.map(\.riskRatio).max() else {
            return nil
        }

        let winners = risks.filter { abs($0.riskRatio - maxRisk) < 0.0001 }
        let windows = winners.map { $0.window.kind }
        let text = text(for: windows)
        let percent = winners.compactMap { $0.window.percentRemaining }.min()
        let resetAt = winners.compactMap { $0.window.resetAt }.min()
        let first = winners[0]
        let expected = (first.prediction.predictedConsumption * 10).rounded() / 10
        let remaining = percent.map(String.init) ?? "未知"

        return QuotaBottleneckEvaluation(
            windows: windows,
            remainingPercent: percent,
            resetAt: resetAt,
            text: text,
            explanation: "\(text) 按最近 30 天周中/周末小时习惯预测为当前瓶颈：\(first.prediction.matchDescription)预计消耗约 \(expected)%，当前剩余 \(remaining)% 。"
        )
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
        let cycleDuration: Double = window.kind == .fiveHour ? 5.0 : 168.0
        let supportScore = (remainingHours / cycleDuration) / max(0.5, Double(percent))

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
            explanation = "\(text) 重置周期内剩余额度相对紧张（归一化支撑度 \(formatSupportScore(first.supportScore))），是当前使用的主要限制。"
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

    private static func formatSupportScore(_ score: Double) -> String {
        let rounded = (score * 1000).rounded() / 1000
        return String(format: "%.3f", rounded)
    }

    private struct WindowScore {
        var window: QuotaWindowSnapshot
        var burnRate: Double
        var resetHours: Double
        var timeToDrainHours: Double?
        var deficitHours: Double
        var supportScore: Double
    }

    private struct UsageRisk {
        var window: QuotaWindowSnapshot
        var prediction: QuotaUsagePrediction
        var riskRatio: Double
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
        let matched = [fiveHour, weekly].filter { $0.percentRemaining == percentRemaining }
        // 方案5：两窗口数据完全相同时（单一数据源退化），默认选择 5 小时额度
        if matched.count == 2, fiveHour.resetAt == weekly.resetAt {
            return [.fiveHour]
        }
        return matched.map(\.kind)
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
