import Foundation
import Security

enum KeychainTokenStore {
    private static let service = "com.qihui.codex-quota-menubar"
    private static let telegramBotTokenAccount = "telegram-bot-token"
    private static let barkDeviceKeyAccount = "bark-device-key"

    static func loadTelegramBotToken() -> String {
        loadToken(account: telegramBotTokenAccount)
    }

    static func saveTelegramBotToken(_ token: String) throws {
        try saveToken(token, account: telegramBotTokenAccount)
    }

    static func deleteTelegramBotToken() throws {
        try deleteToken(account: telegramBotTokenAccount)
    }

    static func loadBarkDeviceKey() -> String {
        loadToken(account: barkDeviceKeyAccount)
    }

    static func saveBarkDeviceKey(_ deviceKey: String) throws {
        try saveToken(deviceKey, account: barkDeviceKeyAccount)
    }

    static func deleteBarkDeviceKey() throws {
        try deleteToken(account: barkDeviceKeyAccount)
    }

    private static func loadToken(account: String) -> String {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return ""
        }
        return token
    }

    private static func saveToken(_ token: String, account: String) throws {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedToken.isEmpty {
            try deleteToken(account: account)
            return
        }

        let data = Data(trimmedToken.utf8)
        var query = baseQuery(account: account)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus))
        }

        query[kSecValueData as String] = data
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
        }
    }

    private static func deleteToken(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
