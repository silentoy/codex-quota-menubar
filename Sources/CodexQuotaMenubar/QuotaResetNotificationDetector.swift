import Foundation

enum QuotaResetReason: String, Sendable {
    case scheduled
    case suspectedProviderAdjustment
    case unknownRecovery
}

struct QuotaResetNotificationEvent: Equatable, Sendable {
    let kind: QuotaWindowKind
    let reason: QuotaResetReason
    let percentRemaining: Int
    let resetID: String

    var message: String {
        switch reason {
        case .scheduled:
            return "Codex \(kind.rawValue)已到期重置，当前剩余 \(percentRemaining)%。"
        case .suspectedProviderAdjustment:
            return "Codex \(kind.rawValue)疑似由服务商调整，当前剩余 \(percentRemaining)%。"
        case .unknownRecovery:
            return "Codex 额度已恢复，原因暂无法确认，当前剩余 \(percentRemaining)%。"
        }
    }
}

enum QuotaResetNotificationDetector {
    static func events(
        previous: QuotaSnapshot?,
        current: QuotaSnapshot,
        now: Date = Date(),
        notifiedResetIDs: Set<String>
    ) -> [QuotaResetNotificationEvent] {
        guard let previous, !current.failed else { return [] }

        return [
            event(
                kind: .fiveHour,
                previous: previous.fiveHour,
                current: current.fiveHour,
                now: now,
                notifiedResetIDs: notifiedResetIDs
            ),
            event(
                kind: .weekly,
                previous: previous.weekly,
                current: current.weekly,
                now: now,
                notifiedResetIDs: notifiedResetIDs
            ),
        ].compactMap(\.self)
    }

    private static func event(
        kind: QuotaWindowKind,
        previous: QuotaWindowSnapshot,
        current: QuotaWindowSnapshot,
        now: Date,
        notifiedResetIDs: Set<String>
    ) -> QuotaResetNotificationEvent? {
        guard let previousPercent = previous.percentRemaining,
              let currentPercent = current.percentRemaining,
              currentPercent > previousPercent else {
            return nil
        }

        let reason = reason(previous: previous, current: current, now: now, increase: currentPercent - previousPercent)
        guard let reason else { return nil }

        let resetID = resetID(kind: kind, current: current, now: now, reason: reason)
        guard !notifiedResetIDs.contains(resetID) else { return nil }

        return QuotaResetNotificationEvent(
            kind: kind,
            reason: reason,
            percentRemaining: currentPercent,
            resetID: resetID
        )
    }

    private static func reason(
        previous: QuotaWindowSnapshot,
        current: QuotaWindowSnapshot,
        now: Date,
        increase: Int
    ) -> QuotaResetReason? {
        let resetMovedForward = resetMovedForward(previous.resetAt, current.resetAt)

        if let previousResetAt = previous.resetAt,
           previousResetAt <= now,
           resetMovedForward,
           increase >= 10 {
            return .scheduled
        }

        if let previousResetAt = previous.resetAt,
           previousResetAt > now,
           (increase >= 50 || resetMovedUnexpectedly(previous.resetAt, current.resetAt)) {
            return .suspectedProviderAdjustment
        }

        if previous.resetAt == nil || current.resetAt == nil {
            return increase >= 50 ? .unknownRecovery : nil
        }

        return nil
    }

    private static func resetMovedForward(_ previous: Date?, _ current: Date?) -> Bool {
        guard let previous, let current else { return false }
        return current > previous
    }

    private static func resetMovedUnexpectedly(_ previous: Date?, _ current: Date?) -> Bool {
        guard let previous, let current else { return false }
        return current != previous
    }

    private static func resetID(
        kind: QuotaWindowKind,
        current: QuotaWindowSnapshot,
        now: Date,
        reason: QuotaResetReason
    ) -> String {
        let timestamp = Int((current.resetAt ?? now).timeIntervalSince1970)
        return "\(kind.storageKey):\(timestamp):\(reason.rawValue)"
    }
}

extension QuotaWindowKind {
    var storageKey: String {
        switch self {
        case .fiveHour:
            return "fiveHour"
        case .weekly:
            return "weekly"
        }
    }
}
