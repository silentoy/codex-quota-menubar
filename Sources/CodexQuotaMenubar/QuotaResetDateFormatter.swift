import Foundation

enum QuotaResetDateFormatter {
    static func text(
        for date: Date?,
        kind: QuotaWindowKind,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard let date else {
            return "未知"
        }

        switch kind {
        case .fiveHour:
            return fiveHourText(for: date, now: now, calendar: calendar)
        case .weekly:
            return weeklyText(for: date, calendar: calendar)
        }
    }

    private static func fiveHourText(for date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return "今天 \(timeText(for: date, calendar: calendar))"
        }

        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "明天 \(timeText(for: date, calendar: calendar))"
        }

        return fallbackDateText(for: date, calendar: calendar)
    }

    private static func weeklyText(for date: Date, calendar: Calendar) -> String {
        let weekday = calendar.component(.weekday, from: date)
        let weekdayText = weekdayNames[weekday] ?? "周?"
        return "\(weekdayText) \(timeText(for: date, calendar: calendar))"
    }

    private static func timeText(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func fallbackDateText(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "M/d HH:mm"
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
}
