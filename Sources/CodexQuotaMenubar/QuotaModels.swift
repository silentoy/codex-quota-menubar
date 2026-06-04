import Foundation
import SwiftUI

enum QuotaSource: String, CaseIterable, Identifiable, Sendable {
    case codexAuth = "Codex 登录态"
    case local = "本机状态"
    case manual = "手动填写"

    var id: String { rawValue }
}

enum DisplayMode: String, CaseIterable, Identifiable, Sendable {
    case percentage = "百分比"
    case shortStatus = "简短状态"

    var id: String { rawValue }
}

enum QuotaLevel: String, Sendable {
    case normal = "正常"
    case low = "额度偏低"
    case critical = "接近耗尽"
    case unknown = "未知"

    var color: Color {
        switch self {
        case .normal:
            return .primary
        case .low:
            return .orange
        case .critical:
            return .red
        case .unknown:
            return .secondary
        }
    }
}

struct QuotaSnapshot: Sendable {
    var percentRemaining: Int?
    var resetAt: Date?
    var source: QuotaSource
    var detail: String
    var capturedAt: Date
    var failed: Bool

    static func unknown(source: QuotaSource, detail: String, failed: Bool = false) -> QuotaSnapshot {
        QuotaSnapshot(
            percentRemaining: nil,
            resetAt: nil,
            source: source,
            detail: detail,
            capturedAt: Date(),
            failed: failed
        )
    }
}
