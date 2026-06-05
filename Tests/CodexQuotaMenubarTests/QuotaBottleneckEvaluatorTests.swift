import Foundation
import Testing
@testable import CodexQuotaMenubar

struct QuotaBottleneckEvaluatorTests {
    @Test func percentageModeIgnoresHistoryAndUsesLowestRemainingPercent() {
        let now = Date(timeIntervalSince1970: 10_000)
        let snapshot = self.snapshot(
            fiveHour: 80,
            fiveHourReset: now.addingTimeInterval(60 * 60),
            weekly: 20,
            weeklyReset: now.addingTimeInterval(5 * 24 * 60 * 60),
            capturedAt: now
        )
        let history = [
            self.history(
                fiveHour: 100,
                weekly: 20,
                capturedAt: now.addingTimeInterval(-60 * 60)
            )
        ]

        let result = QuotaBottleneckEvaluator.evaluate(
            snapshot: snapshot,
            historyRecords: history,
            mode: .percentage,
            now: now
        )

        #expect(result.windows == [.weekly])
        #expect(result.text == "周额度")
        #expect(result.remainingPercent == 20)
        #expect(result.explanation.contains("按剩余额度百分比判断"))
    }

    @Test func smartModeUsesBurnRateDeficitWhenFiveHourWillRunOutBeforeReset() {
        let now = Date(timeIntervalSince1970: 10_000)
        let snapshot = self.snapshot(
            fiveHour: 30,
            fiveHourReset: now.addingTimeInterval(4 * 60 * 60),
            weekly: 15,
            weeklyReset: now.addingTimeInterval(5 * 24 * 60 * 60),
            capturedAt: now
        )
        let history = [
            self.history(fiveHour: 70, weekly: 15, capturedAt: now.addingTimeInterval(-2 * 60 * 60)),
            self.history(fiveHour: 50, weekly: 15, capturedAt: now.addingTimeInterval(-60 * 60)),
        ]

        let result = QuotaBottleneckEvaluator.evaluate(
            snapshot: snapshot,
            historyRecords: history,
            mode: .smart,
            now: now
        )

        #expect(result.windows == [.fiveHour])
        #expect(result.text == "5 小时额度")
        #expect(result.remainingPercent == 30)
        #expect(result.explanation.contains("预计"))
    }

    @Test func smartModeFallsBackToStaticSupportWhenHistoryHasNoBurnRate() {
        let now = Date(timeIntervalSince1970: 10_000)
        let snapshot = self.snapshot(
            fiveHour: 10,
            fiveHourReset: now.addingTimeInterval(2 * 60),
            weekly: 15,
            weeklyReset: now.addingTimeInterval(5 * 24 * 60 * 60),
            capturedAt: now
        )

        let result = QuotaBottleneckEvaluator.evaluate(
            snapshot: snapshot,
            historyRecords: [],
            mode: .smart,
            now: now
        )

        #expect(result.windows == [.weekly])
        #expect(result.text == "周额度")
        #expect(result.explanation.contains("每 1% 需支撑"))
    }

    @Test func burnRateIgnoresPercentIncreasesAsResetOrProviderAdjustment() {
        let now = Date(timeIntervalSince1970: 10_000)
        let snapshot = self.snapshot(
            fiveHour: 65,
            fiveHourReset: now.addingTimeInterval(3 * 60 * 60),
            weekly: 80,
            weeklyReset: now.addingTimeInterval(5 * 24 * 60 * 60),
            capturedAt: now
        )
        let history = [
            self.history(fiveHour: 40, weekly: 80, capturedAt: now.addingTimeInterval(-2 * 60 * 60)),
            self.history(fiveHour: 90, weekly: 80, capturedAt: now.addingTimeInterval(-60 * 60)),
        ]

        let rate = QuotaBottleneckEvaluator.calculateBurnRate(
            windowKind: .fiveHour,
            snapshot: snapshot,
            historyRecords: history,
            duration: 3 * 60 * 60,
            now: now
        )

        #expect(rate == 25)
    }

    private func snapshot(
        fiveHour: Int?,
        fiveHourReset: Date?,
        weekly: Int?,
        weeklyReset: Date?,
        capturedAt: Date
    ) -> QuotaSnapshot {
        QuotaSnapshot(
            fiveHour: QuotaWindowSnapshot(kind: .fiveHour, percentRemaining: fiveHour, resetAt: fiveHourReset),
            weekly: QuotaWindowSnapshot(kind: .weekly, percentRemaining: weekly, resetAt: weeklyReset),
            source: .codexAuth,
            detail: "",
            capturedAt: capturedAt,
            failed: false
        )
    }

    private func history(fiveHour: Int?, weekly: Int?, capturedAt: Date) -> QuotaHistoryRecord {
        QuotaHistoryRecord(
            fiveHourPercentRemaining: fiveHour,
            weeklyPercentRemaining: weekly,
            capturedAt: capturedAt
        )
    }
}
