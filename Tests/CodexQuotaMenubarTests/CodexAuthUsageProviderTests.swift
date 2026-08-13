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

    @Test func weeklyPrimaryWindowIsNotTreatedAsFiveHour() throws {
        let data = Data("""
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window": {
              "used_percent": 2,
              "limit_window_seconds": 604800,
              "reset_after_seconds": 597929,
              "reset_at": 1787204957
            },
            "secondary_window": null
          }
        }
        """.utf8)

        let snapshot = try CodexAuthUsageProvider.snapshot(fromUsageData: data, capturedAt: Date(timeIntervalSince1970: 1_786_607_028))

        #expect(snapshot.fiveHour.percentRemaining == nil)
        #expect(snapshot.fiveHour.resetAt == nil)
        #expect(snapshot.weekly.percentRemaining == 98)
        #expect(snapshot.weekly.resetAt == Date(timeIntervalSince1970: 1_787_204_957))
        #expect(snapshot.failed == false)
        #expect(snapshot.detail.contains("周额度剩余：98%"))
    }

    @Test func windowDurationsOverridePrimarySecondarySlots() throws {
        let data = Data("""
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window": {
              "used_percent": 10,
              "limit_window_seconds": 604800,
              "reset_at": 1800604800
            },
            "secondary_window": {
              "used_percent": 40,
              "limit_window_seconds": 18000,
              "reset_at": 1800003600
            }
          }
        }
        """.utf8)

        let snapshot = try CodexAuthUsageProvider.snapshot(fromUsageData: data)

        #expect(snapshot.fiveHour.percentRemaining == 60)
        #expect(snapshot.fiveHour.resetAt == Date(timeIntervalSince1970: 1_800_003_600))
        #expect(snapshot.weekly.percentRemaining == 90)
        #expect(snapshot.weekly.resetAt == Date(timeIntervalSince1970: 1_800_604_800))
    }

    @Test func fractionalUsedPercentAndResetAfterSecondsAreParsed() throws {
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let data = Data("""
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window": {
              "used_percent": 18.4,
              "limit_window_seconds": 18000,
              "reset_after_seconds": 3600
            },
            "secondary_window": {
              "used_percent": "86.6",
              "limit_window_seconds": 604800,
              "reset_after_seconds": 86400
            }
          }
        }
        """.utf8)

        let snapshot = try CodexAuthUsageProvider.snapshot(fromUsageData: data, capturedAt: capturedAt)

        #expect(snapshot.fiveHour.percentRemaining == 82)
        #expect(snapshot.fiveHour.resetAt == capturedAt.addingTimeInterval(3600))
        #expect(snapshot.weekly.percentRemaining == 13)
        #expect(snapshot.weekly.resetAt == capturedAt.addingTimeInterval(86400))
    }

    @Test func classifiesFiveHourAndWeeklyDurations() {
        #expect(CodexUsageWindowClassifier.kind(limitWindowSeconds: 18_000) == .fiveHour)
        #expect(CodexUsageWindowClassifier.kind(limitWindowSeconds: 604_800) == .weekly)
        #expect(CodexUsageWindowClassifier.kind(limitWindowSeconds: 86_400) == nil)
        #expect(CodexUsageWindowClassifier.kind(limitWindowSeconds: nil) == nil)
    }

    @Test func parsesResetCreditsResponse() throws {
        let data = Data("""
        {
          "available_count": 2,
          "credits": [
            {
              "status": "available",
              "title": "Full reset (Weekly + 5 hr)",
              "granted_at": "2026-06-18T00:34:52Z",
              "expires_at": "2026-07-18T00:34:52Z"
            },
            {
              "status": "available",
              "title": "Full reset (Weekly + 5 hr)",
              "granted_at": "2026-06-27T00:07:45Z",
              "expires_at": "2026-07-27T00:07:45Z"
            }
          ]
        }
        """.utf8)

        let snapshot = try CodexAuthUsageProvider.resetCredits(
            fromData: data,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        #expect(snapshot.availableCount == 2)
        #expect(snapshot.credits.count == 2)
        #expect(snapshot.credits[0].status == "available")
        #expect(snapshot.credits[0].title == "Full reset (Weekly + 5 hr)")
        #expect(snapshot.credits[0].grantedAt == Date(timeIntervalSince1970: 1_781_742_892))
        #expect(snapshot.credits[0].expiresAt == Date(timeIntervalSince1970: 1_784_334_892))
        #expect(snapshot.earliestAvailableExpiration == Date(timeIntervalSince1970: 1_784_334_892))
        #expect(snapshot.failed == false)
    }

    @Test func invalidResetCreditsResponseThrowsDecodeError() {
        #expect(throws: CodexAuthUsageError.decodeFailed) {
            _ = try CodexAuthUsageProvider.resetCredits(fromData: Data("{".utf8))
        }
    }

    @Test func resetCreditsUnauthorizedErrorMessageIsSafe() {
        let error = CodexAuthUsageError.resetCreditsUnauthorized

        #expect(error.errorDescription?.contains("401") == true)
        #expect(error.errorDescription?.contains("token") == false)
        #expect(error.errorDescription?.contains("Bearer") == false)
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
