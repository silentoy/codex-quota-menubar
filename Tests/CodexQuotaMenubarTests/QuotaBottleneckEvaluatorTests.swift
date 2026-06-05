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
        #expect(result.explanation.contains("归一化支撑度"))
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

    @Test func usageBucketsAccumulateDropsAndActiveRefreshesInSameHour() {
        let calendar = self.calendar()
        let first = date(2026, 6, 3, 10, 5)
        let second = date(2026, 6, 3, 10, 25)
        var buckets: [QuotaUsageHourBucket] = []
        var lastSample: QuotaUsageLastSample?

        QuotaUsageFrequencyRecorder.record(
            snapshot: self.snapshot(fiveHour: 80, fiveHourReset: nil, weekly: 90, weeklyReset: nil, capturedAt: first),
            buckets: &buckets,
            lastSample: &lastSample,
            now: first,
            calendar: calendar
        )
        QuotaUsageFrequencyRecorder.record(
            snapshot: self.snapshot(fiveHour: 74, fiveHourReset: nil, weekly: 88, weeklyReset: nil, capturedAt: second),
            buckets: &buckets,
            lastSample: &lastSample,
            now: second,
            calendar: calendar
        )

        #expect(buckets.count == 1)
        #expect(buckets[0].dayType == .weekday)
        #expect(buckets[0].hour == 10)
        #expect(buckets[0].successRefreshCount == 2)
        #expect(buckets[0].activeRefreshCount == 1)
        #expect(buckets[0].fiveHourConsumedPercent == 6)
        #expect(buckets[0].weeklyConsumedPercent == 2)
    }

    @Test func usageBucketsIgnorePercentIncreases() {
        let calendar = self.calendar()
        let first = date(2026, 6, 3, 10, 5)
        let second = date(2026, 6, 3, 10, 25)
        var buckets: [QuotaUsageHourBucket] = []
        var lastSample: QuotaUsageLastSample?

        QuotaUsageFrequencyRecorder.record(
            snapshot: self.snapshot(fiveHour: 50, fiveHourReset: nil, weekly: 70, weeklyReset: nil, capturedAt: first),
            buckets: &buckets,
            lastSample: &lastSample,
            now: first,
            calendar: calendar
        )
        QuotaUsageFrequencyRecorder.record(
            snapshot: self.snapshot(fiveHour: 95, fiveHourReset: nil, weekly: 71, weeklyReset: nil, capturedAt: second),
            buckets: &buckets,
            lastSample: &lastSample,
            now: second,
            calendar: calendar
        )

        #expect(buckets.count == 1)
        #expect(buckets[0].successRefreshCount == 2)
        #expect(buckets[0].activeRefreshCount == 0)
        #expect(buckets[0].fiveHourConsumedPercent == 0)
        #expect(buckets[0].weeklyConsumedPercent == 0)
    }

    @Test func usageBucketsPruneOlderThanThirtyDays() {
        let calendar = self.calendar()
        let now = date(2026, 6, 30, 10, 0)
        var buckets = [
            self.bucket(day: "2026-05-29", dayType: .weekday, weekday: 6, hour: 10, fiveHour: 4, weekly: 1),
            self.bucket(day: "2026-06-01", dayType: .weekday, weekday: 2, hour: 10, fiveHour: 5, weekly: 1),
        ]

        QuotaUsageFrequencyRecorder.prune(&buckets, now: now, calendar: calendar)

        #expect(buckets.map(\.dayKey) == ["2026-06-01"])
    }

    @Test func usagePredictionPrefersWeekdayHourBuckets() {
        let calendar = self.calendar()
        let now = date(2026, 6, 3, 10, 0) // Wednesday
        let reset = date(2026, 6, 3, 12, 0)
        let buckets = [
            self.bucket(day: "2026-06-02", dayType: .weekday, weekday: 3, hour: 10, fiveHour: 4, weekly: 1),
            self.bucket(day: "2026-05-31", dayType: .weekend, weekday: 1, hour: 10, fiveHour: 40, weekly: 8),
            self.bucket(day: "2026-06-02", dayType: .weekday, weekday: 3, hour: 11, fiveHour: 6, weekly: 1),
        ]

        let prediction = QuotaUsageFrequencyPredictor.predict(
            windowKind: .fiveHour,
            from: now,
            resetAt: reset,
            buckets: buckets,
            calendar: calendar
        )

        #expect(prediction.predictedConsumption == 10)
        #expect(prediction.matchDescription.contains("周中/周末"))
    }

    @Test func usagePredictionPrefersWeekendHourBuckets() {
        let calendar = self.calendar()
        let now = date(2026, 6, 6, 10, 0) // Saturday
        let reset = date(2026, 6, 6, 11, 0)
        let buckets = [
            self.bucket(day: "2026-06-03", dayType: .weekday, weekday: 4, hour: 10, fiveHour: 30, weekly: 8),
            self.bucket(day: "2026-05-31", dayType: .weekend, weekday: 1, hour: 10, fiveHour: 2, weekly: 1),
        ]

        let prediction = QuotaUsageFrequencyPredictor.predict(
            windowKind: .fiveHour,
            from: now,
            resetAt: reset,
            buckets: buckets,
            calendar: calendar
        )

        #expect(prediction.predictedConsumption == 2)
    }

    @Test func usagePredictionFallsBackToSameHourWhenDayTypeHasNoData() {
        let calendar = self.calendar()
        let now = date(2026, 6, 3, 10, 0) // Wednesday
        let reset = date(2026, 6, 3, 11, 0)
        let buckets = [
            self.bucket(day: "2026-05-31", dayType: .weekend, weekday: 1, hour: 10, fiveHour: 7, weekly: 1),
        ]

        let prediction = QuotaUsageFrequencyPredictor.predict(
            windowKind: .fiveHour,
            from: now,
            resetAt: reset,
            buckets: buckets,
            calendar: calendar
        )

        #expect(prediction.predictedConsumption == 7)
        #expect(prediction.matchDescription.contains("相同小时"))
    }

    @Test func smartModeUsesUsageBucketsBeforeShortTermTrend() {
        let calendar = self.calendar()
        let now = date(2026, 6, 3, 10, 0)
        let snapshot = self.snapshot(
            fiveHour: 20,
            fiveHourReset: date(2026, 6, 3, 12, 0),
            weekly: 80,
            weeklyReset: date(2026, 6, 6, 10, 0),
            capturedAt: now
        )
        let buckets = [
            self.bucket(day: "2026-06-02", dayType: .weekday, weekday: 3, hour: 10, fiveHour: 12, weekly: 2),
            self.bucket(day: "2026-06-02", dayType: .weekday, weekday: 3, hour: 11, fiveHour: 12, weekly: 2),
        ]

        let result = QuotaBottleneckEvaluator.evaluate(
            snapshot: snapshot,
            historyRecords: [],
            usageBuckets: buckets,
            mode: .smart,
            now: now,
            calendar: calendar
        )

        #expect(result.windows == [.fiveHour])
        #expect(result.explanation.contains("最近 30 天周中/周末小时习惯"))
    }

    @Test func smartModeFallsBackToNormalizedSupportWhenUsageBucketsDoNotPredictRisk() {
        let calendar = self.calendar()
        let now = date(2026, 6, 6, 20, 0) // Saturday night
        let snapshot = self.snapshot(
            fiveHour: 50,
            fiveHourReset: date(2026, 6, 7, 1, 0),
            weekly: 70,
            weeklyReset: date(2026, 6, 10, 10, 0),
            capturedAt: now
        )
        let buckets = [
            self.bucket(day: "2026-05-31", dayType: .weekend, weekday: 1, hour: 20, fiveHour: 0, weekly: 0),
        ]

        let result = QuotaBottleneckEvaluator.evaluate(
            snapshot: snapshot,
            historyRecords: [],
            usageBuckets: buckets,
            mode: .smart,
            now: now,
            calendar: calendar
        )

        // 归一化后：fiveHour supportScore = (5/5.0)/50 = 0.02，weekly = (86/168.0)/70 ≈ 0.0073
        // fiveHour 在其周期内的防守压力更大
        #expect(result.windows == [.fiveHour])
        #expect(result.explanation.contains("归一化支撑度"))
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

    private func bucket(
        day: String,
        dayType: QuotaUsageDayType,
        weekday: Int,
        hour: Int,
        fiveHour: Double,
        weekly: Double
    ) -> QuotaUsageHourBucket {
        QuotaUsageHourBucket(
            dayKey: day,
            dayType: dayType,
            weekday: weekday,
            hour: hour,
            successRefreshCount: 1,
            activeRefreshCount: fiveHour > 0 || weekly > 0 ? 1 : 0,
            fiveHourConsumedPercent: fiveHour,
            weeklyConsumedPercent: weekly
        )
    }

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = self.calendar()
        components.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }
}
