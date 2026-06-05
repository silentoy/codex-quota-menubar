import Foundation

enum BarkNotificationError: Error, Equatable {
    case missingConfiguration
    case invalidServerURL
    case invalidResponse
    case apiError(String)
    case httpError(Int)
}

struct BarkNotifier: Sendable {
    func send(serverURL: String, deviceKey: String, title: String, body: String) async throws {
        let request = try Self.makeRequest(
            serverURL: serverURL,
            deviceKey: deviceKey,
            title: title,
            body: body
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validateResponse(data: data, response: response)
    }

    static func validateResponse(data: Data, response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BarkNotificationError.invalidResponse
        }

        let message = barkResponseMessage(from: data)
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let message {
                throw BarkNotificationError.apiError(message)
            }
            throw BarkNotificationError.httpError(httpResponse.statusCode)
        }

        if let code = barkResponseCode(from: data), code != 200 {
            throw BarkNotificationError.apiError(message ?? "Bark 返回 code \(code)")
        }
    }

    static func makeRequest(serverURL: String, deviceKey: String, title: String, body: String) throws -> URLRequest {
        let trimmedServerURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDeviceKey = normalizeDeviceKey(deviceKey)
        guard !trimmedServerURL.isEmpty, !trimmedDeviceKey.isEmpty else {
            throw BarkNotificationError.missingConfiguration
        }

        guard var components = URLComponents(string: trimmedServerURL),
              components.scheme != nil,
              components.host != nil else {
            throw BarkNotificationError.invalidServerURL
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = basePath.isEmpty ? "/push" : "/\(basePath)/push"

        guard let url = components.url else {
            throw BarkNotificationError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "device_key": trimmedDeviceKey,
            "title": title,
            "body": body,
            "group": "Codex Quota",
            "level": "timeSensitive",
        ])
        return request
    }

    private static func normalizeDeviceKey(_ deviceKey: String) -> String {
        let trimmedDeviceKey = deviceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmedDeviceKey),
              components.scheme != nil,
              components.host != nil else {
            return trimmedDeviceKey
        }

        return components.path
            .split(separator: "/")
            .first
            .map(String.init) ?? ""
    }

    private static func barkResponseCode(from data: Data) -> Int? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["code"] as? Int
    }

    private static func barkResponseMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? String,
              !message.isEmpty else {
            return nil
        }
        return message
    }
}
