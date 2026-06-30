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
