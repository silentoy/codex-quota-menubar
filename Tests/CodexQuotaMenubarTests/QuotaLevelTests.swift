import Testing
@testable import CodexQuotaMenubar

struct QuotaLevelTests {
    @Test func unknownPercentHasUnknownLevel() {
        #expect(QuotaLevel.classify(percent: nil, lowThreshold: 20) == .unknown)
    }

    @Test func fivePercentOrLessIsCritical() {
        #expect(QuotaLevel.classify(percent: 5, lowThreshold: 20) == .critical)
    }

    @Test func percentAtLowThresholdIsLow() {
        #expect(QuotaLevel.classify(percent: 20, lowThreshold: 20) == .low)
    }

    @Test func percentAboveLowThresholdIsNormal() {
        #expect(QuotaLevel.classify(percent: 21, lowThreshold: 20) == .normal)
    }
}
