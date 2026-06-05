import Foundation

enum QuotaResetDateFormatter {
    static func text(
        for date: Date?,
        kind: QuotaWindowKind,
        now: Date = Date(),
        calendar: Calendar = .current,
        lang: AppLanguage = .zh
    ) -> String {
        guard let date else {
            return lang == .en ? "Unknown" : "未知"
        }

        switch kind {
        case .fiveHour:
            return fiveHourText(for: date, now: now, calendar: calendar, lang: lang)
        case .weekly:
            return weeklyText(for: date, calendar: calendar, lang: lang)
        }
    }

    private static func fiveHourText(for date: Date, now: Date, calendar: Calendar, lang: AppLanguage) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return lang == .en ? "Today \(timeText(for: date, calendar: calendar, lang: lang))" : "今天 \(timeText(for: date, calendar: calendar, lang: lang))"
        }

        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return lang == .en ? "Tomorrow \(timeText(for: date, calendar: calendar, lang: lang))" : "明天 \(timeText(for: date, calendar: calendar, lang: lang))"
        }

        return fallbackDateText(for: date, calendar: calendar, lang: lang)
    }

    private static func weeklyText(for date: Date, calendar: Calendar, lang: AppLanguage) -> String {
        let weekday = calendar.component(.weekday, from: date)
        let weekdayText = weekdayName(for: weekday, lang: lang)
        return "\(weekdayText) \(timeText(for: date, calendar: calendar, lang: lang))"
    }

    private static func weekdayName(for weekday: Int, lang: AppLanguage) -> String {
        if lang == .en {
            return weekdayNamesEn[weekday] ?? "Sun?"
        }
        return weekdayNames[weekday] ?? "周?"
    }

    private static func timeText(for date: Date, calendar: Calendar, lang: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: lang == .en ? "en_US" : "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func fallbackDateText(for date: Date, calendar: Calendar, lang: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: lang == .en ? "en_US" : "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = lang == .en ? "MMM d HH:mm" : "M/d HH:mm"
        return formatter.string(from: date)
    }

    private static let weekdayNames = [
        1: "周日",
        2: "周一",
        3: "周二",
        4: "周三",
        5: "周四",
        6: "周五",
        7: "周六",
    ]

    private static let weekdayNamesEn = [
        1: "Sunday",
        2: "Monday",
        3: "Tuesday",
        4: "Wednesday",
        5: "Thursday",
        6: "Friday",
        7: "Saturday",
    ]
}
