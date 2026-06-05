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
    let resetAt: Date?
    let resetID: String
    let lang: AppLanguage

    var message: String {
        let title: String
        let emoji: String
        let kindName = kind.localizedName(lang: lang)
        if lang == .en {
            switch reason {
            case .scheduled:
                emoji = "✅"
                title = "Codex \(kindName) has reset"
            case .suspectedProviderAdjustment:
                emoji = "🔄"
                title = "Codex \(kindName) suspected adjustment by provider"
            case .unknownRecovery:
                emoji = "✨"
                title = "Codex quota recovered (reason unconfirmed)"
            }
            return """
            \(emoji) \(Self.bold(title))
            📊 Current Remaining: \(Self.code("\(percentRemaining)%"))
            ⏰ Next Reset: \(Self.code(nextResetText))
            """
        } else {
            switch reason {
            case .scheduled:
                emoji = "✅"
                title = "Codex \(kindName)已到期重置"
            case .suspectedProviderAdjustment:
                emoji = "🔄"
                title = "Codex \(kindName)疑似由服务商调整"
            case .unknownRecovery:
                emoji = "✨"
                title = "Codex 额度已恢复，原因暂无法确认"
            }
            return """
            \(emoji) \(Self.bold(title))
            📊 当前剩余：\(Self.code("\(percentRemaining)%"))
            ⏰ 下次重置：\(Self.code(nextResetText))
            """
        }
    }

    var barkTitle: String {
        let kindName = kind.localizedName(lang: lang)
        if lang == .en {
            switch reason {
            case .scheduled:
                return "Codex \(kindName) Reset"
            case .suspectedProviderAdjustment, .unknownRecovery:
                return "Codex \(kindName) Recovered"
            }
        } else {
            switch reason {
            case .scheduled:
                return "Codex \(kindName)已重置"
            case .suspectedProviderAdjustment, .unknownRecovery:
                return "Codex \(kindName)已恢复"
            }
        }
    }

    func barkBody(companion: QuotaWindowSnapshot) -> String {
        let companionKindName = companion.kind.localizedName(lang: lang)
        if lang == .en {
            return """
            Current Remaining: \(percentRemaining)%
            \(companionKindName): \(Self.percentText(companion.percentRemaining, lang: lang))
            Reset Reason: \(barkReasonText)
            """
        } else {
            return """
            当前剩余：\(percentRemaining)%
            \(companionKindName)：\(Self.percentText(companion.percentRemaining, lang: lang))
            重置原因：\(barkReasonText)
            """
        }
    }

    private var barkReasonText: String {
        if lang == .en {
            switch reason {
            case .scheduled:
                return "Scheduled Reset"
            case .suspectedProviderAdjustment:
                return "Suspected Provider Adjustment"
            case .unknownRecovery:
                return "Unknown Recovery"
            }
        } else {
            switch reason {
            case .scheduled:
                return "到期重置"
            case .suspectedProviderAdjustment:
                return "疑似服务商调整"
            case .unknownRecovery:
                return "未知恢复"
            }
        }
    }

    private var nextResetText: String {
        guard let resetAt else { return lang == .en ? "Unknown" : "未知" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: lang == .en ? "en_US" : "zh_CN")
        formatter.dateFormat = "yyyy/M/d HH:mm"
        return formatter.string(from: resetAt)
    }

    private static func bold(_ text: String) -> String {
        "*\(escapeMarkdownV2(text))*"
    }

    private static func code(_ text: String) -> String {
        "`\(text.replacingOccurrences(of: "`", with: "\\`"))`"
    }

    private static func percentText(_ percent: Int?, lang: AppLanguage) -> String {
        percent.map { "\($0)%" } ?? (lang == .en ? "Unknown" : "未知")
    }

    private static func escapeMarkdownV2(_ text: String) -> String {
        let specialCharacters = CharacterSet(charactersIn: "_*[]()~`>#+-=|{}.!")
        var escaped = ""
        for scalar in text.unicodeScalars {
            if specialCharacters.contains(scalar) {
                escaped.append("\\")
            }
            escaped.append(String(scalar))
        }
        return escaped
    }
}

enum QuotaResetNotificationDetector {
    static func events(
        previous: QuotaSnapshot?,
        current: QuotaSnapshot,
        now: Date = Date(),
        lang: AppLanguage = .zh,
        notifiedResetIDs: Set<String>
    ) -> [QuotaResetNotificationEvent] {
        guard let previous, !current.failed else { return [] }

        return [
            event(
                kind: .fiveHour,
                previous: previous.fiveHour,
                current: current.fiveHour,
                now: now,
                lang: lang,
                notifiedResetIDs: notifiedResetIDs
            ),
            event(
                kind: .weekly,
                previous: previous.weekly,
                current: current.weekly,
                now: now,
                lang: lang,
                notifiedResetIDs: notifiedResetIDs
            ),
        ].compactMap(\.self)
    }

    private static func event(
        kind: QuotaWindowKind,
        previous: QuotaWindowSnapshot,
        current: QuotaWindowSnapshot,
        now: Date,
        lang: AppLanguage,
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
            resetAt: current.resetAt,
            resetID: resetID,
            lang: lang
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
