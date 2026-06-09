import Foundation
import Testing
@testable import CodexQuotaMenubar

@MainActor
struct QuotaStoreTests {
    @Test func adaptiveIntervalCalculatesCorrectly() {
        let store = QuotaStore()
        
        // 1. When adaptive frequency is disabled, should return refreshIntervalMinutes
        store.adaptiveFrequency = false
        store.refreshIntervalMinutes = 10
        #expect(store.currentRefreshIntervalMinutes == 10)
        
        store.refreshIntervalMinutes = 30
        #expect(store.currentRefreshIntervalMinutes == 30)
        
        // 2. Enable adaptive frequency
        store.adaptiveFrequency = true
        
        // 3. Test different percent remaining scenarios with 0 burn rate (no history)
        
        // Case A: Remaining <= 5% -> 3 mins
        setQuota(store: store, fiveHour: 5, weekly: 100)
        #expect(store.currentRefreshIntervalMinutes == 3)
        
        setQuota(store: store, fiveHour: 2, weekly: 2)
        #expect(store.currentRefreshIntervalMinutes == 3)
        
        // Case B: Remaining <= 20% -> 5 mins
        setQuota(store: store, fiveHour: 15, weekly: 80)
        #expect(store.currentRefreshIntervalMinutes == 5)
        
        setQuota(store: store, fiveHour: 20, weekly: 20)
        #expect(store.currentRefreshIntervalMinutes == 5)
        
        // Case C: Remaining <= 50% -> 10 mins
        setQuota(store: store, fiveHour: 30, weekly: 90)
        #expect(store.currentRefreshIntervalMinutes == 10)
        
        setQuota(store: store, fiveHour: 50, weekly: 50)
        #expect(store.currentRefreshIntervalMinutes == 10)
        
        // Case D: Remaining > 50% -> 20 mins (idle period)
        setQuota(store: store, fiveHour: 60, weekly: 80)
        #expect(store.currentRefreshIntervalMinutes == 20)
        
        // Case E: Remaining == 0% and reset date is in the future -> 20 mins (depleted & waiting)
        setQuota(store: store, fiveHour: 0, weekly: 100, resetAt: Date().addingTimeInterval(3600))
        #expect(store.currentRefreshIntervalMinutes == 20)
        
        // Case F: Remaining == 0% but reset date has passed -> 3 mins (restored dynamic adaptive, polling for new data)
        setQuota(store: store, fiveHour: 0, weekly: 100, resetAt: Date().addingTimeInterval(-60))
        #expect(store.currentRefreshIntervalMinutes == 3)
        
        // Case G: Weekly is low (15%) but 5-hour is high (100%) -> 10 mins (optimized: no high-frequency polling for week-long periods unless there's burn rate)
        setQuota(store: store, fiveHour: 100, weekly: 15)
        #expect(store.currentRefreshIntervalMinutes == 10)
    }
    
    private func setQuota(store: QuotaStore, fiveHour: Int?, weekly: Int?, resetAt: Date? = nil) {
        let mockSnapshot = QuotaSnapshot(
            fiveHour: QuotaWindowSnapshot(kind: .fiveHour, percentRemaining: fiveHour, resetAt: resetAt),
            weekly: QuotaWindowSnapshot(kind: .weekly, percentRemaining: weekly, resetAt: resetAt),
            source: .codexAuth,
            detail: "",
            capturedAt: Date(),
            failed: false
        )
        store.setSnapshotForTesting(mockSnapshot)
    }
}
