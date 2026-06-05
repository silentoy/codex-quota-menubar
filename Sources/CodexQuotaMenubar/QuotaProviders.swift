import Foundation

protocol QuotaProviding: Sendable {
    func fetch() async -> QuotaSnapshot
}

struct CodexAuthUsageProvider: QuotaProviding, Sendable {
    private let authURL: URL
    private let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private let refreshURL = URL(string: "https://auth.openai.com/oauth/token")!
    private let codexClientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    init(authURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")) {
        self.authURL = authURL
    }

    func fetch() async -> QuotaSnapshot {
        do {
            let auth = try readAuthFile()
            guard var accessToken = auth.tokens?.accessToken else {
                throw CodexAuthUsageError.missingAccessToken
            }

            if isTokenExpired(accessToken), let refreshToken = auth.tokens?.refreshToken {
                accessToken = try await refreshAccessToken(refreshToken)
            } else if isTokenExpired(accessToken) {
                throw CodexAuthUsageError.tokenRefreshFailed
            }

            let data = try await fetchUsage(accessToken: accessToken, accountID: accountID(from: auth))
            return try Self.snapshot(fromUsageData: data)
        } catch {
            return .unknown(
                source: .codexAuth,
                detail: "读取 Codex 登录态失败：\(error.localizedDescription)",
                failed: true
            )
        }
    }

    private func readAuthFile() throws -> CodexAuthFile {
        guard FileManager.default.fileExists(atPath: authURL.path) else {
            throw CodexAuthUsageError.authFileMissing(authURL.path)
        }
        let data = try Data(contentsOf: authURL)
        return try JSONDecoder().decode(CodexAuthFile.self, from: data)
    }

    private func fetchUsage(accessToken: String, accountID: String?) async throws -> Data {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        if let accountID, !accountID.isEmpty {
            request.addValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CodexAuthUsageError.invalidResponse
        }
        guard 200...299 ~= http.statusCode else {
            throw CodexAuthUsageError.httpError(http.statusCode)
        }

        return data
    }

    private func refreshAccessToken(_ refreshToken: String) async throws -> String {
        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": codexClientID
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
            throw CodexAuthUsageError.tokenRefreshFailed
        }

        let decoded = try JSONDecoder().decode(CodexTokenRefreshResponse.self, from: data)
        return decoded.accessToken
    }

    static func snapshot(fromUsageData data: Data, capturedAt: Date = Date()) throws -> QuotaSnapshot {
        let response: CodexUsageResponse
        do {
            response = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
        } catch {
            throw CodexAuthUsageError.decodeFailed
        }
        return snapshot(from: response, capturedAt: capturedAt)
    }

    private static func snapshot(from response: CodexUsageResponse, capturedAt: Date) -> QuotaSnapshot {
        let sessionUsed = response.rateLimit?.primaryWindow?.usedPercent
        let weeklyUsed = response.rateLimit?.secondaryWindow?.usedPercent
        let sessionRemaining = sessionUsed.map { max(0, min(100, 100 - $0)) }
        let weeklyRemaining = weeklyUsed.map { max(0, min(100, 100 - $0)) }

        let plan = response.planType ?? "unknown"
        let sessionText = sessionRemaining.map { "\($0)%" } ?? "未知"
        let weeklyText = weeklyRemaining.map { "\($0)%" } ?? "未知"
        let failed = sessionRemaining == nil && weeklyRemaining == nil
        let detail: String
        if failed {
            detail = "ChatGPT usage 接口结构可能已变化，未读取到 primary_window 或 secondary_window。计划：\(plan)。"
        } else {
            detail = "通过 ~/.codex/auth.json 调用 ChatGPT usage 接口。计划：\(plan)，短周期剩余：\(sessionText)，周额度剩余：\(weeklyText)。"
        }

        return QuotaSnapshot(
            fiveHour: QuotaWindowSnapshot(
                kind: .fiveHour,
                percentRemaining: sessionRemaining,
                resetAt: response.rateLimit?.primaryWindow?.resetDate
            ),
            weekly: QuotaWindowSnapshot(
                kind: .weekly,
                percentRemaining: weeklyRemaining,
                resetAt: response.rateLimit?.secondaryWindow?.resetDate
            ),
            source: .codexAuth,
            detail: detail,
            capturedAt: capturedAt,
            failed: failed
        )
    }

    private func accountID(from auth: CodexAuthFile) -> String? {
        if let accountID = auth.tokens?.accountID, !accountID.isEmpty {
            return accountID
        }

        guard let idToken = auth.tokens?.idToken,
              let payload = decodeJWTPayload(idToken),
              let authInfo = payload["https://api.openai.com/auth"] as? [String: Any],
              let accountID = authInfo["chatgpt_account_id"] as? String,
              !accountID.isEmpty else {
            return nil
        }

        return accountID
    }

    private func isTokenExpired(_ token: String) -> Bool {
        guard let payload = decodeJWTPayload(token),
              let exp = payload["exp"] as? TimeInterval else {
            return true
        }

        return Date(timeIntervalSince1970: exp) < Date().addingTimeInterval(60)
    }

    private func decodeJWTPayload(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }

        var base64 = String(segments[1])
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        base64 = base64.replacingOccurrences(of: "-", with: "+")
        base64 = base64.replacingOccurrences(of: "_", with: "/")

        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

private struct CodexAuthFile: Codable, Sendable {
    let tokens: CodexTokens?
}

private struct CodexTokens: Codable, Sendable {
    let idToken: String?
    let accessToken: String?
    let refreshToken: String?
    let accountID: String?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case accountID = "account_id"
    }
}

private struct CodexUsageResponse: Codable, Sendable {
    let planType: String?
    let rateLimit: CodexRateLimit?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
    }
}

private struct CodexRateLimit: Codable, Sendable {
    let limitReached: Bool?
    let primaryWindow: CodexWindow?
    let secondaryWindow: CodexWindow?

    enum CodingKeys: String, CodingKey {
        case limitReached = "limit_reached"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct CodexWindow: Codable, Sendable {
    let usedPercent: Int?
    let resetAt: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetAt = "reset_at"
    }

    var resetDate: Date? {
        resetAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
}

private struct CodexTokenRefreshResponse: Codable, Sendable {
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

private enum CodexAuthUsageError: LocalizedError {
    case authFileMissing(String)
    case missingAccessToken
    case decodeFailed
    case invalidResponse
    case httpError(Int)
    case tokenRefreshFailed

    var errorDescription: String? {
        switch self {
        case .authFileMissing(let path):
            return "未找到 \(path)，请先打开 Codex 完成登录。"
        case .missingAccessToken:
            return "auth.json 中没有 ChatGPT access_token，请重新登录 Codex。"
        case .decodeFailed:
            return "ChatGPT usage 接口响应解析失败，接口结构可能已变化。"
        case .invalidResponse:
            return "ChatGPT usage 接口返回格式无效。"
        case .httpError(let status):
            return "ChatGPT usage 接口 HTTP \(status)。"
        case .tokenRefreshFailed:
            return "Codex access_token 已过期，刷新失败，请重新登录 Codex。"
        }
    }
}

struct ManualProvider: QuotaProviding, Sendable {
    let percentRemaining: Int
    let resetAt: Date?
    let note: String

    func fetch() async -> QuotaSnapshot {
        QuotaSnapshot.singleWindow(
            percentRemaining: max(0, min(100, percentRemaining)),
            resetAt: resetAt,
            source: .manual,
            detail: note.isEmpty ? "使用手动填写的额度。" : note,
            failed: false
        )
    }
}

struct LocalCodexProvider: QuotaProviding, Sendable {
    func fetch() async -> QuotaSnapshot {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let codexDir = home.appendingPathComponent(".codex")

        guard fileManager.fileExists(atPath: codexDir.path) else {
            return .unknown(source: .local, detail: "未找到 ~/.codex 目录。", failed: true)
        }

        let candidates = [
            codexDir.appendingPathComponent(".codex-global-state.json"),
            codexDir.appendingPathComponent("version.json")
        ]

        for url in candidates where fileManager.fileExists(atPath: url.path) {
            if let snapshot = parseQuotaSnapshot(from: url) {
                return snapshot
            }
        }

        return .unknown(
            source: .local,
            detail: "本机 Codex 状态中未发现公开额度字段；未读取 auth.json、Cookie 或网页登录态。"
        )
    }

    private func parseQuotaSnapshot(from url: URL) -> QuotaSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        let flattened = flatten(object)
        let quotaCandidates = flattened.filter { key, _ in
            let lower = key.lowercased()
            return lower.contains("quota") || lower.contains("limit") || lower.contains("remaining")
        }

        for (key, value) in quotaCandidates {
            if let percent = normalizedPercent(value) {
                return QuotaSnapshot.singleWindow(
                    percentRemaining: percent,
                    resetAt: findResetDate(in: flattened),
                    source: .local,
                    detail: "从 \(url.lastPathComponent) 的 \(key) 字段读取。",
                    failed: false
                )
            }
        }

        return nil
    }

    private func flatten(_ value: Any, prefix: String = "") -> [(String, Any)] {
        if let dictionary = value as? [String: Any] {
            return dictionary.flatMap { key, child in
                flatten(child, prefix: prefix.isEmpty ? key : "\(prefix).\(key)")
            }
        }

        if let array = value as? [Any] {
            return array.enumerated().flatMap { index, child in
                flatten(child, prefix: "\(prefix)[\(index)]")
            }
        }

        return [(prefix, value)]
    }

    private func normalizedPercent(_ value: Any) -> Int? {
        let number: Double?
        if let double = value as? Double {
            number = double
        } else if let int = value as? Int {
            number = Double(int)
        } else if let string = value as? String {
            number = Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            number = nil
        }

        guard let number else { return nil }
        if number >= 0, number <= 1 {
            return Int((number * 100).rounded())
        }
        if number >= 0, number <= 100 {
            return Int(number.rounded())
        }
        return nil
    }

    private func findResetDate(in flattened: [(String, Any)]) -> Date? {
        let formatter = ISO8601DateFormatter()
        for (key, value) in flattened {
            let lower = key.lowercased()
            guard lower.contains("reset") || lower.contains("renew") else { continue }
            if let string = value as? String, let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }
}
