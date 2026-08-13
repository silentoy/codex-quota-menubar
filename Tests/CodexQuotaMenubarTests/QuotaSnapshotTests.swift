import Foundation
import Testing
@testable import CodexQuotaMenubar

struct QuotaSnapshotTests {
    @Test func fiveHourIsBottleneckWhenItHasLowerRemainingPercent() {
        let snapshot = snapshot(fiveHour: 24, weekly: 80)

        #expect(snapshot.bottleneckText == "5 小时额度")
        #expect(snapshot.bottleneckRemainingPercent == 24)
    }

    @Test func weeklyIsBottleneckWhenItHasLowerRemainingPercent() {
        let snapshot = snapshot(fiveHour: 90, weekly: 17)

        #expect(snapshot.bottleneckText == "周额度")
        #expect(snapshot.bottleneckRemainingPercent == 17)
    }

    @Test func equalKnownWindowsWithSameResetDefaultToFiveHour() {
        let snapshot = snapshot(fiveHour: 42, weekly: 42)

        #expect(snapshot.bottleneckText == "5 小时额度")
        #expect(snapshot.bottleneckRemainingPercent == 42)
    }

    @Test func onlyKnownWindowBecomesBottleneck() {
        let snapshot = snapshot(fiveHour: nil, weekly: 31)

        #expect(snapshot.bottleneckText == "周额度")
        #expect(snapshot.bottleneckRemainingPercent == 31)
    }

    @Test func unknownWindowsHaveNoBottleneck() {
        let snapshot = snapshot(fiveHour: nil, weekly: nil)

        #expect(snapshot.bottleneckText == "未知")
        #expect(snapshot.bottleneckRemainingPercent == nil)
    }

    @Test func ringOuterFallsBackToWeeklyWhenFiveHourIsMissing() {
        let snapshot = snapshot(fiveHour: nil, weekly: 98)

        #expect(snapshot.ringOuterPercentRemaining == 98)
        #expect(snapshot.ringInnerPercentRemaining == 98)
    }

    @Test func ringOuterPrefersFiveHourWhenBothWindowsExist() {
        let snapshot = snapshot(fiveHour: 18, weekly: 61)

        #expect(snapshot.ringOuterPercentRemaining == 18)
        #expect(snapshot.ringInnerPercentRemaining == 61)
    }

    private func snapshot(fiveHour: Int?, weekly: Int?) -> QuotaSnapshot {
        QuotaSnapshot(
            fiveHour: QuotaWindowSnapshot(kind: .fiveHour, percentRemaining: fiveHour, resetAt: nil),
            weekly: QuotaWindowSnapshot(kind: .weekly, percentRemaining: weekly, resetAt: nil),
            source: .codexAuth,
            detail: "",
            capturedAt: Date(timeIntervalSince1970: 0),
            failed: false
        )
    }
}
