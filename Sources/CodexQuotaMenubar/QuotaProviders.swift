import Foundation

protocol QuotaProviding: Sendable {
    func fetch() async -> QuotaSnapshot
}

struct CodexAuthUsageProvider: QuotaProviding, Sendable {
    private let authURL: URL
    private let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private let resetCreditsURL = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!
    private let refreshURL = URL(string: "https://auth.openai.com/oauth/token")!
    private let codexClientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    init(authURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")) {
        self.authURL = authURL
    }

    func fetch() async -> QuotaSnapshot {
        let result = await fetchAll()
        return result.usage
    }

    func fetchAll() async -> (usage: QuotaSnapshot, resetCredits: ResetCreditsState) {
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

            let accountID = accountID(from: auth)
            async let usage = fetchUsageSnapshot(accessToken: accessToken, accountID: accountID)
            async let resetCredits = fetchResetCreditsState(accessToken: accessToken, accountID: accountID)
            return (await usage, await resetCredits)
        } catch {
            return (
                .unknown(
                    source: .codexAuth,
                    detail: "读取 Codex 登录态失败：\(error.localizedDescription)",
                    failed: true
                ),
                .failed(error.localizedDescription)
            )
        }
    }

    private func fetchUsageSnapshot(accessToken: String, accountID: String?) async -> QuotaSnapshot {
        do {
            let data = try await fetchUsage(accessToken: accessToken, accountID: accountID)
            return try Self.snapshot(fromUsageData: data)
        } catch {
            return .unknown(
                source: .codexAuth,
                detail: "读取 Codex 登录态失败：\(error.localizedDescription)",
                failed: true
            )
        }
    }

    func fetchResetCreditsSnapshot() async throws -> ResetCreditsSnapshot {
        let auth = try readAuthFile()
        guard var accessToken = auth.tokens?.accessToken else {
            throw CodexAuthUsageError.missingAccessToken
        }

        if isTokenExpired(accessToken), let refreshToken = auth.tokens?.refreshToken {
            accessToken = try await refreshAccessToken(refreshToken)
        } else if isTokenExpired(accessToken) {
            throw CodexAuthUsageError.tokenRefreshFailed
        }

        let data = try await fetchResetCredits(accessToken: accessToken, accountID: accountID(from: auth))
        return try Self.resetCredits(fromData: data)
    }

    private func fetchResetCreditsState(accessToken: String, accountID: String?) async -> ResetCreditsState {
        do {
            let data = try await fetchResetCredits(accessToken: accessToken, accountID: accountID)
            return .loaded(try Self.resetCredits(fromData: data))
        } catch {
            return .failed(error.localizedDescription)
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

    private func fetchResetCredits(accessToken: String, accountID: String?) async throws -> Data {
        var request = URLRequest(url: resetCreditsURL)
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
            if http.statusCode == 401 {
                throw CodexAuthUsageError.resetCreditsUnauthorized
            }
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

    static func resetCredits(fromData data: Data, capturedAt: Date = Date()) throws -> ResetCreditsSnapshot {
        let response: CodexResetCreditsResponse
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let raw = try container.decode(String.self)
                if let date = Self.iso8601Date(from: raw) {
                    return date
                }
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO-8601 date."
                )
            }
            response = try decoder.decode(CodexResetCreditsResponse.self, from: data)
        } catch {
            throw CodexAuthUsageError.decodeFailed
        }

        return ResetCreditsSnapshot(
            availableCount: response.availableCount,
            credits: response.credits.map {
                ResetCredit(
                    status: $0.status,
                    title: $0.title,
                    grantedAt: $0.grantedAt,
                    expiresAt: $0.expiresAt
                )
            },
            capturedAt: capturedAt,
            failed: false,
            detail: ""
        )
    }

    private static func iso8601Date(from raw: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: raw) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    private static func snapshot(from response: CodexUsageResponse, capturedAt: Date) -> QuotaSnapshot {
        let assigned = CodexUsageWindowClassifier.assign(rateLimit: response.rateLimit)
        let sessionRemaining = assigned.fiveHour?.remainingPercent
        let weeklyRemaining = assigned.weekly?.remainingPercent

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
                resetAt: assigned.fiveHour?.resetDate(capturedAt: capturedAt)
            ),
            weekly: QuotaWindowSnapshot(
                kind: .weekly,
                percentRemaining: weeklyRemaining,
                resetAt: assigned.weekly?.resetDate(capturedAt: capturedAt)
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

private struct CodexUsageResponse: Decodable, Sendable {
    let planType: String?
    let rateLimit: CodexRateLimit?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
    }
}

struct CodexRateLimit: Decodable, Sendable {
    let limitReached: Bool?
    let primaryWindow: CodexWindow?
    let secondaryWindow: CodexWindow?

    enum CodingKeys: String, CodingKey {
        case limitReached = "limit_reached"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }

    init(
        limitReached: Bool? = nil,
        primaryWindow: CodexWindow? = nil,
        secondaryWindow: CodexWindow? = nil
    ) {
        self.limitReached = limitReached
        self.primaryWindow = primaryWindow
        self.secondaryWindow = secondaryWindow
    }
}

private struct CodexResetCreditsResponse: Codable, Sendable {
    let availableCount: Int
    let credits: [CodexResetCreditResponse]

    enum CodingKeys: String, CodingKey {
        case availableCount = "available_count"
        case credits
    }
}

private struct CodexResetCreditResponse: Codable, Sendable {
    let status: String
    let title: String
    let grantedAt: Date?
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case status
        case title
        case grantedAt = "granted_at"
        case expiresAt = "expires_at"
    }
}

struct CodexWindow: Decodable, Sendable {
    let usedPercent: Int?
    let resetAt: Int?
    let limitWindowSeconds: Int?
    let resetAfterSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetAt = "reset_at"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAfterSeconds = "reset_after_seconds"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = container.decodeFlexibleInt(forKey: .usedPercent)
        resetAt = container.decodeFlexibleInt(forKey: .resetAt)
        limitWindowSeconds = container.decodeFlexibleInt(forKey: .limitWindowSeconds)
        resetAfterSeconds = container.decodeFlexibleInt(forKey: .resetAfterSeconds)
    }

    init(
        usedPercent: Int?,
        resetAt: Int? = nil,
        limitWindowSeconds: Int? = nil,
        resetAfterSeconds: Int? = nil
    ) {
        self.usedPercent = usedPercent
        self.resetAt = resetAt
        self.limitWindowSeconds = limitWindowSeconds
        self.resetAfterSeconds = resetAfterSeconds
    }

    var isEmpty: Bool {
        usedPercent == nil && resetAt == nil && limitWindowSeconds == nil && resetAfterSeconds == nil
    }

    var remainingPercent: Int? {
        usedPercent.map { max(0, min(100, 100 - $0)) }
    }

    func resetDate(capturedAt: Date) -> Date? {
        if let resetAt {
            return Date(timeIntervalSince1970: TimeInterval(resetAt))
        }
        if let resetAfterSeconds {
            return capturedAt.addingTimeInterval(TimeInterval(resetAfterSeconds))
        }
        return nil
    }
}

enum CodexUsageWindowClassifier {
    // ChatGPT usage no longer guarantees primary=5h / secondary=weekly.
    // Some plans only return a weekly window in primary_window.
    static let fiveHourSeconds = 5 * 3600
    static let weeklySeconds = 7 * 24 * 3600

    private struct Candidate {
        let window: CodexWindow
        let slotKind: QuotaWindowKind
        let classifiedKind: QuotaWindowKind?
    }

    static func kind(limitWindowSeconds: Int?) -> QuotaWindowKind? {
        guard let limitWindowSeconds, limitWindowSeconds > 0 else { return nil }
        if limitWindowSeconds <= 12 * 3600 {
            return .fiveHour
        }
        if limitWindowSeconds >= 2 * 24 * 3600 {
            return .weekly
        }
        return nil
    }

    static func assign(rateLimit: CodexRateLimit?) -> (fiveHour: CodexWindow?, weekly: CodexWindow?) {
        guard let rateLimit else { return (nil, nil) }

        var candidates: [Candidate] = []
        if let primary = rateLimit.primaryWindow, !primary.isEmpty {
            candidates.append(
                Candidate(
                    window: primary,
                    slotKind: .fiveHour,
                    classifiedKind: kind(limitWindowSeconds: primary.limitWindowSeconds)
                )
            )
        }
        if let secondary = rateLimit.secondaryWindow, !secondary.isEmpty {
            candidates.append(
                Candidate(
                    window: secondary,
                    slotKind: .weekly,
                    classifiedKind: kind(limitWindowSeconds: secondary.limitWindowSeconds)
                )
            )
        }

        var fiveHour: CodexWindow?
        var weekly: CodexWindow?

        fiveHour = closestWindow(in: candidates, kind: .fiveHour, targetSeconds: fiveHourSeconds)
        weekly = closestWindow(in: candidates, kind: .weekly, targetSeconds: weeklySeconds)

        for candidate in candidates {
            guard candidate.classifiedKind == nil else { continue }
            switch candidate.slotKind {
            case .fiveHour where fiveHour == nil:
                fiveHour = candidate.window
            case .weekly where weekly == nil:
                weekly = candidate.window
            case .fiveHour, .weekly:
                if fiveHour == nil {
                    fiveHour = candidate.window
                } else if weekly == nil {
                    weekly = candidate.window
                }
            }
        }

        return (fiveHour, weekly)
    }

    private static func closestWindow(
        in candidates: [Candidate],
        kind: QuotaWindowKind,
        targetSeconds: Int
    ) -> CodexWindow? {
        candidates
            .filter { $0.classifiedKind == kind }
            .min { lhs, rhs in
                let left = abs((lhs.window.limitWindowSeconds ?? targetSeconds) - targetSeconds)
                let right = abs((rhs.window.limitWindowSeconds ?? targetSeconds) - targetSeconds)
                return left < right
            }?
            .window
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value.rounded())
        }
        if let raw = try? decodeIfPresent(String.self, forKey: key),
           let value = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return Int(value.rounded())
        }
        return nil
    }
}

private struct CodexTokenRefreshResponse: Codable, Sendable {
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

enum CodexAuthUsageError: LocalizedError, Equatable {
    case authFileMissing(String)
    case missingAccessToken
    case decodeFailed
    case invalidResponse
    case httpError(Int)
    case tokenRefreshFailed
    case resetCreditsUnauthorized

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
        case .resetCreditsUnauthorized:
            return "重置次数接口 HTTP 401：凭证失效或未携带 Authorization header。"
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
