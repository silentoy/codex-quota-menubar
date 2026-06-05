import Foundation
import Testing
@testable import CodexQuotaMenubar

struct CodexAuthUsageProviderTests {
    @Test func parsesUsageWindowsIntoRemainingPercents() throws {
        let data = usageJSON(primaryUsed: 64, secondaryUsed: 23)
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let snapshot = try CodexAuthUsageProvider.snapshot(fromUsageData: data, capturedAt: capturedAt)

        #expect(snapshot.fiveHour.percentRemaining == 36)
        #expect(snapshot.weekly.percentRemaining == 77)
        #expect(snapshot.source == .codexAuth)
        #expect(snapshot.capturedAt == capturedAt)
        #expect(snapshot.failed == false)
    }

    @Test func missingUsageWindowsProduceUnknownFailedSnapshot() throws {
        let data = Data("""
        {
          "plan_type": "plus",
          "rate_limit": {}
        }
        """.utf8)

        let snapshot = try CodexAuthUsageProvider.snapshot(fromUsageData: data, capturedAt: Date(timeIntervalSince1970: 0))

        #expect(snapshot.fiveHour.percentRemaining == nil)
        #expect(snapshot.weekly.percentRemaining == nil)
        #expect(snapshot.failed == true)
    }

    private func usageJSON(primaryUsed: Int, secondaryUsed: Int) -> Data {
        Data("""
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window": {
              "used_percent": \(primaryUsed),
              "reset_at": 1800003600
            },
            "secondary_window": {
              "used_percent": \(secondaryUsed),
              "reset_at": 1800604800
            }
          }
        }
        """.utf8)
    }
}
