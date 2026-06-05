import Foundation
import Testing
@testable import CodexQuotaMenubar

struct QuotaResetDateFormatterTests {
    @Test func fiveHourResetUsesTodayOrTomorrow() {
        let calendar = Calendar(identifier: .gregorian)
        let now = date(calendar, 2026, 6, 5, 13, 10)

        let today = date(calendar, 2026, 6, 5, 18, 30)
        let tomorrow = date(calendar, 2026, 6, 6, 9, 5)

        #expect(QuotaResetDateFormatter.text(for: today, kind: .fiveHour, now: now, calendar: calendar) == "今天 18:30")
        #expect(QuotaResetDateFormatter.text(for: tomorrow, kind: .fiveHour, now: now, calendar: calendar) == "明天 09:05")
    }

    @Test func weeklyResetUsesWeekdayAndTime() {
        let calendar = Calendar(identifier: .gregorian)
        let now = date(calendar, 2026, 6, 5, 13, 10)
        let resetAt = date(calendar, 2026, 6, 8, 7, 0)

        #expect(QuotaResetDateFormatter.text(for: resetAt, kind: .weekly, now: now, calendar: calendar) == "周一 07:00")
    }

    @Test func missingResetDateUsesUnknown() {
        #expect(QuotaResetDateFormatter.text(for: nil, kind: .fiveHour) == "未知")
    }

    private func date(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
