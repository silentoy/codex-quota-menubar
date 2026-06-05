import Foundation
import Testing
@testable import CodexQuotaMenubar

struct BarkNotifierTests {
    @Test func buildsPushRequest() throws {
        let request = try BarkNotifier.makeRequest(
            serverURL: "https://api.day.app",
            deviceKey: "abc123",
            title: "Codex 5 小时额度已重置",
            body: "当前剩余：100%\n周额度：61%\n重置原因：到期重置"
        )

        #expect(request.url?.absoluteString == "https://api.day.app/push")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json; charset=utf-8")

        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["device_key"] as? String == "abc123")
        #expect(json?["title"] as? String == "Codex 5 小时额度已重置")
        #expect(json?["body"] as? String == "当前剩余：100%\n周额度：61%\n重置原因：到期重置")
        #expect(json?["group"] as? String == "Codex Quota")
        #expect(json?["level"] as? String == "timeSensitive")
    }

    @Test func trimsServerURLTrailingSlash() throws {
        let request = try BarkNotifier.makeRequest(
            serverURL: "https://api.day.app/",
            deviceKey: "abc123",
            title: "Codex 额度提醒",
            body: "Bark 测试消息"
        )

        #expect(request.url?.absoluteString == "https://api.day.app/push")
    }

    @Test func appendsPushToServerURLPath() throws {
        let request = try BarkNotifier.makeRequest(
            serverURL: "https://example.com/bark/",
            deviceKey: "abc123",
            title: "Codex 额度提醒",
            body: "Bark 测试消息"
        )

        #expect(request.url?.absoluteString == "https://example.com/bark/push")
    }

    @Test func acceptsFullBarkURLAsDeviceKey() throws {
        let request = try BarkNotifier.makeRequest(
            serverURL: "https://api.day.app",
            deviceKey: "https://api.day.app/abc123/Codex%20%E6%B5%8B%E8%AF%95",
            title: "Codex 额度提醒",
            body: "Bark 测试消息"
        )

        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["device_key"] as? String == "abc123")
    }

    @Test func detectsBarkAPIErrorMessage() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "code": 400,
            "message": "failed to get device token: not found",
        ])
        let response = HTTPURLResponse(
            url: URL(string: "https://api.day.app/push")!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: nil
        )!

        #expect(throws: BarkNotificationError.apiError("failed to get device token: not found")) {
            try BarkNotifier.validateResponse(data: data, response: response)
        }
    }

    @Test func missingServerURLOrDeviceKeyDoesNotBuildRequest() {
        #expect(throws: BarkNotificationError.missingConfiguration) {
            try BarkNotifier.makeRequest(
                serverURL: "",
                deviceKey: "abc123",
                title: "Codex 额度提醒",
                body: "Bark 测试消息"
            )
        }
        #expect(throws: BarkNotificationError.missingConfiguration) {
            try BarkNotifier.makeRequest(
                serverURL: "https://api.day.app",
                deviceKey: "",
                title: "Codex 额度提醒",
                body: "Bark 测试消息"
            )
        }
    }

    @Test func invalidServerURLDoesNotBuildRequest() {
        #expect(throws: BarkNotificationError.invalidServerURL) {
            try BarkNotifier.makeRequest(
                serverURL: "not a url",
                deviceKey: "abc123",
                title: "Codex 额度提醒",
                body: "Bark 测试消息"
            )
        }
    }
}
