import Foundation

enum TelegramNotificationError: Error, Equatable {
    case missingConfiguration
    case invalidResponse
    case httpError(Int)
}

struct TelegramNotifier: Sendable {
    func send(token: String, chatID: String, text: String) async throws {
        let request = try Self.makeRequest(token: token, chatID: chatID, text: text)
        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TelegramNotificationError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw TelegramNotificationError.httpError(httpResponse.statusCode)
        }
    }

    static func makeRequest(token: String, chatID: String, text: String) throws -> URLRequest {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedChatID = chatID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty, !trimmedChatID.isEmpty else {
            throw TelegramNotificationError.missingConfiguration
        }

        let url = URL(string: "https://api.telegram.org/bot\(trimmedToken)/sendMessage")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "chat_id": trimmedChatID,
            "parse_mode": "MarkdownV2",
            "text": text,
        ])
        return request
    }
}
