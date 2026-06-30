# Reset Credits Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Codex reset credit availability and expiration details to the menu bar panel using a collapsible drawer.

**Architecture:** Reuse the existing Codex auth provider flow for token reading, token refresh, account ID derivation, and request headers. Store reset credit data separately from quota usage so reset-credit failures do not invalidate the main quota snapshot. Render a SwiftUI drawer modeled after the existing quota trend disclosure card.

**Tech Stack:** Swift 6, SwiftUI, Foundation `URLSession`, Swift Testing.

---

### Task 1: Reset Credit Models And Decoder

**Files:**
- Modify: `Sources/CodexQuotaMenubar/QuotaModels.swift`
- Modify: `Sources/CodexQuotaMenubar/QuotaProviders.swift`
- Test: `Tests/CodexQuotaMenubarTests/CodexAuthUsageProviderTests.swift`

- [ ] **Step 1: Write failing decoder tests**

Add tests covering `available_count`, credit fields, local earliest expiration, and invalid JSON failure:

```swift
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

    let snapshot = try CodexAuthUsageProvider.resetCredits(fromData: data, capturedAt: Date(timeIntervalSince1970: 1_800_000_000))

    #expect(snapshot.availableCount == 2)
    #expect(snapshot.credits.count == 2)
    #expect(snapshot.credits[0].status == "available")
    #expect(snapshot.credits[0].title == "Full reset (Weekly + 5 hr)")
    #expect(snapshot.credits[0].grantedAt == Date(timeIntervalSince1970: 1_787_182_492))
    #expect(snapshot.credits[0].expiresAt == Date(timeIntervalSince1970: 1_789_774_492))
    #expect(snapshot.earliestAvailableExpiration == Date(timeIntervalSince1970: 1_789_774_492))
    #expect(snapshot.failed == false)
}

@Test func invalidResetCreditsResponseThrowsDecodeError() {
    #expect(throws: CodexAuthUsageError.decodeFailed) {
        _ = try CodexAuthUsageProvider.resetCredits(fromData: Data("{".utf8))
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter CodexAuthUsageProviderTests`

Expected: FAIL because reset credit types and parsing method do not exist.

- [ ] **Step 3: Implement models and parser**

Add `ResetCreditSnapshot`, `ResetCredit`, `CodexResetCreditsResponse`, and `CodexResetCreditResponse`. Add `CodexAuthUsageProvider.resetCredits(fromData:capturedAt:)`.

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --filter CodexAuthUsageProviderTests`

Expected: PASS.

### Task 2: Provider Fetch Integration

**Files:**
- Modify: `Sources/CodexQuotaMenubar/QuotaProviders.swift`
- Test: `Tests/CodexQuotaMenubarTests/CodexAuthUsageProviderTests.swift`

- [ ] **Step 1: Write failing error mapping test**

Add a test asserting HTTP 401 maps to a reset-credit auth error without exposing credentials:

```swift
@Test func resetCreditsUnauthorizedErrorMessageIsSafe() {
    let error = CodexAuthUsageError.resetCreditsUnauthorized

    #expect(error.errorDescription?.contains("401") == true)
    #expect(error.errorDescription?.contains("token") == false)
    #expect(error.errorDescription?.contains("Bearer") == false)
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter CodexAuthUsageProviderTests`

Expected: FAIL because the new error case does not exist.

- [ ] **Step 3: Implement fetch method**

Add `resetCreditsURL`, `fetchResetCredits(accessToken:accountID:)`, and `fetchResetCreditsSnapshot()` to `CodexAuthUsageProvider`. Use the same token refresh and account ID behavior as usage fetch. Map HTTP 401 to `resetCreditsUnauthorized`.

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --filter CodexAuthUsageProviderTests`

Expected: PASS.

### Task 3: Store State And Formatting

**Files:**
- Modify: `Sources/CodexQuotaMenubar/QuotaStore.swift`
- Test: `Tests/CodexQuotaMenubarTests/QuotaStoreTests.swift`

- [ ] **Step 1: Write failing formatting tests**

Add tests covering collapsed summary, zero state, failure state, and earliest expiration:

```swift
@Test func resetCreditsSummaryUsesEarliestExpiration() {
    let store = QuotaStore()
    store.setResetCreditsForTesting(.loaded(
        availableCount: 2,
        credits: [
            ResetCredit(status: "available", title: "Later", grantedAt: Date(timeIntervalSince1970: 1_800_000_000), expiresAt: Date(timeIntervalSince1970: 1_900_000_000)),
            ResetCredit(status: "available", title: "Sooner", grantedAt: Date(timeIntervalSince1970: 1_700_000_000), expiresAt: Date(timeIntervalSince1970: 1_800_000_000))
        ],
        capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
    ))

    #expect(store.resetCreditsCountText == "2 次")
    #expect(store.resetCreditsSubtitleText.contains("最近"))
}

@Test func resetCreditsSummaryHandlesEmptyAndFailureStates() {
    let store = QuotaStore()
    store.setResetCreditsForTesting(.loaded(availableCount: 0, credits: [], capturedAt: Date()))
    #expect(store.resetCreditsCountText == "0 次")
    #expect(store.resetCreditsSubtitleText == "暂无可用重置")

    store.setResetCreditsForTesting(.failed("HTTP 401"))
    #expect(store.resetCreditsCountText == "--")
    #expect(store.resetCreditsSubtitleText == "读取失败")
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter QuotaStoreTests`

Expected: FAIL because store reset-credit state and formatting do not exist.

- [ ] **Step 3: Implement store state**

Add published `resetCredits`, formatter helpers, and a testing setter. Refresh reset credits alongside quota usage and preserve prior reset credits when only reset-credit fetch fails.

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --filter QuotaStoreTests`

Expected: PASS.

### Task 4: SwiftUI Drawer

**Files:**
- Modify: `Sources/CodexQuotaMenubar/ContentView.swift`

- [ ] **Step 1: Add drawer view**

Add `resetCreditsSection` between `quotaSections` and `chartSection`. Use existing `glassCard`, `OS27.Padding.card`, chevron rotation, divider style, and `OS27.Motion.expand`.

- [ ] **Step 2: Add credit row view**

Add a compact private `ResetCreditRow` with title, status pill, granted/expires rows, and earliest-expiration warm color.

- [ ] **Step 3: Build**

Run: `swift build`

Expected: PASS.

### Task 5: Final Verification

**Files:**
- No source changes expected.

- [ ] **Step 1: Run full test suite**

Run: `swift test`

Expected: PASS.

- [ ] **Step 2: Run project check script**

Run: `scripts/check.sh`

Expected: PASS.

