import Foundation
import Testing
@testable import CodexQuotaMenubar

struct TelegramNotifierTests {
    @Test func buildsSendMessageRequest() throws {
        let request = try TelegramNotifier.makeRequest(
            token: "123:abc",
            chatID: "456",
            text: "Codex 测试"
        )

        #expect(request.url?.absoluteString == "https://api.telegram.org/bot123:abc/sendMessage")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: String]
        #expect(json?["chat_id"] == "456")
        #expect(json?["text"] == "Codex 测试")
    }

    @Test func missingTokenOrChatIDDoesNotBuildRequest() {
        #expect(throws: TelegramNotificationError.missingConfiguration) {
            try TelegramNotifier.makeRequest(token: "", chatID: "456", text: "Codex 测试")
        }
        #expect(throws: TelegramNotificationError.missingConfiguration) {
            try TelegramNotifier.makeRequest(token: "123:abc", chatID: "", text: "Codex 测试")
        }
    }
}
