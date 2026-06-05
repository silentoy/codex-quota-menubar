import Foundation
import Testing
@testable import CodexQuotaMenubar

struct QuotaResetNotificationDetectorTests {
    @Test func detectsExpiredResetAsScheduledReset() {
        let oldReset = Date(timeIntervalSince1970: 1_800_000_000)
        let newReset = Date(timeIntervalSince1970: 1_800_018_000)
        let now = Date(timeIntervalSince1970: 1_800_000_060)

        let events = QuotaResetNotificationDetector.events(
            previous: snapshot(fiveHour: window(.fiveHour, 4, oldReset), weekly: window(.weekly, 60, nil)),
            current: snapshot(fiveHour: window(.fiveHour, 100, newReset), weekly: window(.weekly, 60, nil)),
            now: now,
            notifiedResetIDs: []
        )

        #expect(events.count == 1)
        #expect(events.first?.kind == .fiveHour)
        #expect(events.first?.reason == .scheduled)
        #expect(events.first?.message == """
        ✅ *Codex 5 小时额度已到期重置*
        📊 当前剩余：`100%`
        ⏰ 下次重置：`2027/1/15 21:00`
        """)
        #expect(events.first?.barkTitle == "Codex 5 小时额度已重置")
        #expect(events.first?.barkBody(companion: window(.weekly, 60, nil)) == """
        当前剩余：100%
        周额度：60%
        重置原因：到期重置
        """)
    }

    @Test func detectsEarlyLargeRecoveryAsSuspectedProviderAdjustment() {
        let oldReset = Date(timeIntervalSince1970: 1_800_000_000)
        let now = Date(timeIntervalSince1970: 1_799_999_000)

        let events = QuotaResetNotificationDetector.events(
            previous: snapshot(fiveHour: window(.fiveHour, 8, oldReset), weekly: window(.weekly, 60, nil)),
            current: snapshot(fiveHour: window(.fiveHour, 95, oldReset), weekly: window(.weekly, 60, nil)),
            now: now,
            notifiedResetIDs: []
        )

        #expect(events.count == 1)
        #expect(events.first?.kind == .fiveHour)
        #expect(events.first?.reason == .suspectedProviderAdjustment)
        #expect(events.first?.message == """
        🔄 *Codex 5 小时额度疑似由服务商调整*
        📊 当前剩余：`95%`
        ⏰ 下次重置：`2027/1/15 16:00`
        """)
        #expect(events.first?.barkTitle == "Codex 5 小时额度已恢复")
        #expect(events.first?.barkBody(companion: window(.weekly, nil, nil)) == """
        当前剩余：95%
        周额度：未知
        重置原因：疑似服务商调整
        """)
    }

    @Test func skipsAlreadyNotifiedResetID() {
        let oldReset = Date(timeIntervalSince1970: 1_800_000_000)
        let newReset = Date(timeIntervalSince1970: 1_800_018_000)
        let now = Date(timeIntervalSince1970: 1_800_000_060)
        let notifiedID = "fiveHour:1800018000:scheduled"

        let events = QuotaResetNotificationDetector.events(
            previous: snapshot(fiveHour: window(.fiveHour, 4, oldReset), weekly: window(.weekly, 60, nil)),
            current: snapshot(fiveHour: window(.fiveHour, 100, newReset), weekly: window(.weekly, 60, nil)),
            now: now,
            notifiedResetIDs: [notifiedID]
        )

        #expect(events.isEmpty)
    }

    @Test func detectsBothWindowsIndependently() {
        let fiveOldReset = Date(timeIntervalSince1970: 1_800_000_000)
        let fiveNewReset = Date(timeIntervalSince1970: 1_800_018_000)
        let weeklyOldReset = Date(timeIntervalSince1970: 1_800_000_000)
        let weeklyNewReset = Date(timeIntervalSince1970: 1_800_604_800)
        let now = Date(timeIntervalSince1970: 1_800_000_060)

        let events = QuotaResetNotificationDetector.events(
            previous: snapshot(fiveHour: window(.fiveHour, 3, fiveOldReset), weekly: window(.weekly, 2, weeklyOldReset)),
            current: snapshot(fiveHour: window(.fiveHour, 100, fiveNewReset), weekly: window(.weekly, 100, weeklyNewReset)),
            now: now,
            notifiedResetIDs: []
        )

        #expect(events.map(\.kind) == [.fiveHour, .weekly])
        #expect(events.allSatisfy { $0.reason == .scheduled })
    }

    @Test func doesNotNotifyWithoutPreviousSnapshot() {
        let reset = Date(timeIntervalSince1970: 1_800_018_000)

        let events = QuotaResetNotificationDetector.events(
            previous: nil,
            current: snapshot(fiveHour: window(.fiveHour, 100, reset), weekly: window(.weekly, 60, nil)),
            now: Date(timeIntervalSince1970: 1_800_000_060),
            notifiedResetIDs: []
        )

        #expect(events.isEmpty)
    }

    private func snapshot(fiveHour: QuotaWindowSnapshot, weekly: QuotaWindowSnapshot) -> QuotaSnapshot {
        QuotaSnapshot(
            fiveHour: fiveHour,
            weekly: weekly,
            source: .codexAuth,
            detail: "",
            capturedAt: Date(timeIntervalSince1970: 0),
            failed: false
        )
    }

    private func window(_ kind: QuotaWindowKind, _ percent: Int?, _ resetAt: Date?) -> QuotaWindowSnapshot {
        QuotaWindowSnapshot(kind: kind, percentRemaining: percent, resetAt: resetAt)
    }
}
