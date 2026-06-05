import AppKit
import Foundation
import SwiftUI

@MainActor
final class QuotaStore: ObservableObject {
    @AppStorage("refreshIntervalMinutes") var refreshIntervalMinutes = 10 {
        willSet { objectWillChange.send() }
    }
    @AppStorage("displayMode") var displayModeRaw = DisplayMode.ring.rawValue {
        willSet { objectWillChange.send() }
    }
    @AppStorage("bottleneckMode") var bottleneckModeRaw = BottleneckMode.percentage.rawValue {
        willSet { objectWillChange.send() }
    }
    @AppStorage("lowThreshold") var lowThreshold = 20 {
        willSet { objectWillChange.send() }
    }
    @AppStorage("source") var sourceRaw = QuotaSource.codexAuth.rawValue {
        willSet { objectWillChange.send() }
    }
    @AppStorage("didDefaultCodexAuthSource") private var didDefaultCodexAuthSource = false {
        willSet { objectWillChange.send() }
    }
    @AppStorage("manualPercent") var manualPercent = 50 {
        willSet { objectWillChange.send() }
    }
    @AppStorage("manualResetAt") var manualResetAt = "" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("manualNote") var manualNote = "" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("launchAtLogin") var launchAtLogin = false {
        willSet { objectWillChange.send() }
    }
    @AppStorage("telegramEnabled") var telegramEnabled = false {
        willSet { objectWillChange.send() }
    }
    @AppStorage("telegramChatID") var telegramChatID = "" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("telegramNotifyFiveHourReset") var telegramNotifyFiveHourReset = true {
        willSet { objectWillChange.send() }
    }
    @AppStorage("telegramNotifyWeeklyReset") var telegramNotifyWeeklyReset = true {
        willSet { objectWillChange.send() }
    }
    @AppStorage("telegramNotifiedResetIDs") private var telegramNotifiedResetIDsRaw = "" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("barkEnabled") var barkEnabled = false {
        willSet { objectWillChange.send() }
    }
    @AppStorage("barkServerURL") var barkServerURL = "https://api.day.app" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("barkNotifyFiveHourReset") var barkNotifyFiveHourReset = true {
        willSet { objectWillChange.send() }
    }
    @AppStorage("barkNotifyWeeklyReset") var barkNotifyWeeklyReset = true {
        willSet { objectWillChange.send() }
    }
    @AppStorage("barkNotifiedResetIDs") private var barkNotifiedResetIDsRaw = "" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("quotaHistoryRecords") private var quotaHistoryRecordsRaw = "" {
        willSet { objectWillChange.send() }
    }

    @Published private(set) var snapshot: QuotaSnapshot = .unknown(
        source: .codexAuth,
        detail: "等待首次刷新。"
    )
    @Published private(set) var bottleneckEvaluation = QuotaBottleneckEvaluator.evaluate(
        snapshot: .unknown(source: .codexAuth, detail: "等待首次刷新。"),
        historyRecords: [],
        mode: .percentage
    )
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSendingTelegramTest = false
    @Published private(set) var isSendingBarkTest = false
    @Published private(set) var statusMessage = "等待首次刷新。"
    @Published var telegramBotToken = "" {
        willSet { objectWillChange.send() }
    }
    @Published var barkDeviceKey = "" {
        willSet { objectWillChange.send() }
    }

    private var timer: Timer?
    private var lastManualRefreshAt: Date?
    private let telegramNotifier = TelegramNotifier()
    private let barkNotifier = BarkNotifier()

    init() {
        telegramBotToken = KeychainTokenStore.loadTelegramBotToken()
        barkDeviceKey = KeychainTokenStore.loadBarkDeviceKey()
        if !didDefaultCodexAuthSource {
            sourceRaw = QuotaSource.codexAuth.rawValue
            didDefaultCodexAuthSource = true
        }
        startTimer()
        observeWake()
        Task {
            await refresh(force: true)
        }
    }

    var source: QuotaSource {
        // 固定为 Codex 登录态，不再允许用户切换
        .codexAuth
    }

    var displayMode: DisplayMode {
        DisplayMode(rawValue: displayModeRaw) ?? .ring
    }

    var bottleneckMode: BottleneckMode {
        BottleneckMode(rawValue: bottleneckModeRaw) ?? .percentage
    }

    var level: QuotaLevel {
        level(for: snapshot.percentRemaining)
    }

    var menuTitle: String {
        if isRefreshing {
            return "Codex ..."
        }

        switch displayMode {
        case .ring:
            return ""
        case .percentage:
            if let percent = snapshot.percentRemaining {
                return "Codex \(percent)%"
            }
            return "Codex --"
        }
    }

    var menuColor: Color {
        level.color
    }

    var lastRefreshText: String {
        Self.relativeFormatter.localizedString(for: snapshot.capturedAt, relativeTo: Date())
    }

    var resetText: String {
        QuotaResetDateFormatter.text(for: bottleneckEvaluation.resetAt, kind: bottleneck ?? .fiveHour)
    }

    var bottleneckWindows: [QuotaWindowKind] {
        bottleneckEvaluation.windows
    }

    var bottleneck: QuotaWindowKind? {
        bottleneckWindows.count == 1 ? bottleneckWindows.first : nil
    }

    var bottleneckText: String {
        bottleneckEvaluation.text
    }

    var bottleneckExplanation: String {
        bottleneckEvaluation.explanation
    }

    var bottleneckSummaryText: String {
        guard let percent = bottleneckEvaluation.remainingPercent else {
            return "暂未读取到精确额度。"
        }
        return "\(bottleneckText) · 剩余 \(percent)% · \(resetText)"
    }

    func level(for percent: Int?) -> QuotaLevel {
        QuotaLevel.classify(percent: percent, lowThreshold: lowThreshold)
    }

    func percentText(_ percent: Int?) -> String {
        percent.map { "\($0)%" } ?? "未知"
    }

    func resetText(for window: QuotaWindowSnapshot) -> String {
        QuotaResetDateFormatter.text(for: window.resetAt, kind: window.kind)
    }

    func accessibilityLabel() -> String {
        let fiveHourLevel = level(for: snapshot.fiveHour.percentRemaining).rawValue
        let weeklyLevel = level(for: snapshot.weekly.percentRemaining).rawValue
        return "Codex 额度，5 小时\(fiveHourLevel)，周额度\(weeklyLevel)"
    }

    func updateTimer() {
        startTimer()
    }

    func refreshIfStale() {
        guard Date().timeIntervalSince(snapshot.capturedAt) > 60 else { return }
        Task {
            await refresh(force: false)
        }
    }

    func manualRefresh() {
        if let lastManualRefreshAt, Date().timeIntervalSince(lastManualRefreshAt) < 3 {
            statusMessage = "刷新太频繁，请稍等。"
            return
        }

        self.lastManualRefreshAt = Date()
        Task {
            await refresh(force: true)
        }
    }

    func refresh(force: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        statusMessage = "正在刷新..."

        let provider = makeProvider()
        let result = await provider.fetch()
        let previousSnapshot = snapshot

        if result.failed, snapshot.percentRemaining != nil, !force {
            statusMessage = "读取失败，显示上次结果。"
        } else {
            snapshot = result
            rememberHistoryIfNeeded(result)
            updateBottleneckEvaluation()
            if result.failed {
                statusMessage = "读取失败。"
            } else if result.percentRemaining == nil {
                statusMessage = "未读取到额度。"
            } else {
                statusMessage = "刚刚更新。"
            }
        }

        if !result.failed {
            await sendQuotaResetNotifications(previous: previousSnapshot, current: result)
        }

        isRefreshing = false
    }

    func saveTelegramBotToken(_ token: String) {
        telegramBotToken = token
        do {
            try KeychainTokenStore.saveTelegramBotToken(token)
        } catch {
            statusMessage = "保存 Telegram Token 失败。"
        }
    }

    func saveBarkDeviceKey(_ deviceKey: String) {
        barkDeviceKey = deviceKey
        do {
            try KeychainTokenStore.saveBarkDeviceKey(deviceKey)
        } catch {
            statusMessage = "保存 Bark Device Key 失败。"
        }
    }

    func sendTelegramTestMessage() {
        guard !isSendingTelegramTest else { return }
        isSendingTelegramTest = true
        Task {
            _ = await sendTelegramMessage("Codex Quota Telegram 测试消息。")
            isSendingTelegramTest = false
        }
    }

    func sendBarkTestMessage() {
        guard !isSendingBarkTest else { return }
        isSendingBarkTest = true
        Task {
            _ = await sendBarkMessage(
                title: "Codex 额度提醒",
                body: "Bark 测试消息\n如果你看到这条通知，说明推送已配置成功。"
            )
            isSendingBarkTest = false
        }
    }

    func openCodex() {
        let candidates = [
            URL(fileURLWithPath: "/Applications/Codex.app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Codex.app")
        ]

        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return
        }

        if let appURL = URL(string: "x-codex://"), NSWorkspace.shared.open(appURL) {
            return
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func syncLaunchAtLoginState() {
        let plistPath = launchAgentPlistPath
        let exists = FileManager.default.fileExists(atPath: plistPath)
        if launchAtLogin != exists {
            launchAtLogin = exists
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let plistPath = launchAgentPlistPath
        let fm = FileManager.default

        if enabled {
            guard let appPath = Bundle.main.bundlePath as String?,
                  appPath.hasSuffix(".app") else {
                launchAtLogin = false
                statusMessage = "开机启动需以 .app 形式运行。"
                return
            }

            let launchAgentsDir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/LaunchAgents")
            try? fm.createDirectory(atPath: launchAgentsDir, withIntermediateDirectories: true)

            let plist: [String: Any] = [
                "Label": launchAgentLabel,
                "ProgramArguments": ["\(appPath)/Contents/MacOS/CodexQuotaMenubar"],
                "RunAtLoad": true,
                "KeepAlive": false,
            ]

            let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            if let data, fm.createFile(atPath: plistPath, contents: data) {
                launchAtLogin = true
                statusMessage = "已开启开机启动。"
            } else {
                launchAtLogin = false
                statusMessage = "写入 LaunchAgent 失败。"
            }
        } else {
            try? fm.removeItem(atPath: plistPath)
            launchAtLogin = false
            statusMessage = "已关闭开机启动。"
        }
    }

    private var launchAgentLabel: String {
        "com.qihui.codex-quota-menubar"
    }

    private var launchAgentPlistPath: String {
        let home = NSHomeDirectory()
        return "\(home)/Library/LaunchAgents/\(launchAgentLabel).plist"
    }

    private func makeProvider() -> QuotaProviding {
        // 固定使用 Codex 登录态 provider
        CodexAuthUsageProvider()
    }

    private var historyRecords: [QuotaHistoryRecord] {
        get {
            guard let data = quotaHistoryRecordsRaw.data(using: .utf8),
                  let records = try? JSONDecoder().decode([QuotaHistoryRecord].self, from: data) else {
                return []
            }
            return records
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let raw = String(data: data, encoding: .utf8) else {
                return
            }
            quotaHistoryRecordsRaw = raw
        }
    }

    private func rememberHistoryIfNeeded(_ snapshot: QuotaSnapshot) {
        guard !snapshot.failed,
              snapshot.fiveHour.percentRemaining != nil || snapshot.weekly.percentRemaining != nil else {
            return
        }

        var records = historyRecords
        records.append(
            QuotaHistoryRecord(
                fiveHourPercentRemaining: snapshot.fiveHour.percentRemaining,
                weeklyPercentRemaining: snapshot.weekly.percentRemaining,
                capturedAt: snapshot.capturedAt
            )
        )

        let cutoff = Date().addingTimeInterval(-24 * 3600)
        historyRecords = Array(
            records
                .filter { $0.capturedAt >= cutoff }
                .sorted { $0.capturedAt < $1.capturedAt }
                .suffix(50)
        )
    }

    func updateBottleneckEvaluation() {
        bottleneckEvaluation = QuotaBottleneckEvaluator.evaluate(
            snapshot: snapshot,
            historyRecords: historyRecords,
            mode: bottleneckMode
        )
    }

    private func sendQuotaResetNotifications(previous: QuotaSnapshot, current: QuotaSnapshot) async {
        await sendTelegramQuotaResetNotifications(previous: previous, current: current)
        await sendBarkQuotaResetNotifications(previous: previous, current: current)
    }

    private func sendTelegramQuotaResetNotifications(previous: QuotaSnapshot, current: QuotaSnapshot) async {
        guard telegramEnabled else { return }

        let events = QuotaResetNotificationDetector.events(
            previous: previous,
            current: current,
            notifiedResetIDs: telegramNotifiedResetIDs
        )
        let enabledEvents = events.filter { event in
            switch event.kind {
            case .fiveHour:
                return telegramNotifyFiveHourReset
            case .weekly:
                return telegramNotifyWeeklyReset
            }
        }
        guard !enabledEvents.isEmpty else { return }

        for event in enabledEvents {
            if await sendTelegramMessage(event.message) {
                rememberTelegramNotifiedResetID(event.resetID)
            }
        }
    }

    private func sendBarkQuotaResetNotifications(previous: QuotaSnapshot, current: QuotaSnapshot) async {
        guard barkEnabled else { return }

        let events = QuotaResetNotificationDetector.events(
            previous: previous,
            current: current,
            notifiedResetIDs: barkNotifiedResetIDs
        )
        let enabledEvents = events.filter { event in
            switch event.kind {
            case .fiveHour:
                return barkNotifyFiveHourReset
            case .weekly:
                return barkNotifyWeeklyReset
            }
        }
        guard !enabledEvents.isEmpty else { return }

        for event in enabledEvents {
            if await sendBarkMessage(
                title: event.barkTitle,
                body: event.barkBody(companion: barkCompanionWindow(for: event, current: current))
            ) {
                rememberBarkNotifiedResetID(event.resetID)
            }
        }
    }

    private func sendTelegramMessage(_ message: String) async -> Bool {
        do {
            try await telegramNotifier.send(
                token: telegramBotToken,
                chatID: telegramChatID,
                text: message
            )
            statusMessage = "已发送 Telegram 通知。"
            return true
        } catch TelegramNotificationError.missingConfiguration {
            statusMessage = "请先填写 Telegram Token 和 Chat ID。"
        } catch {
            statusMessage = "Telegram 通知发送失败。"
        }
        return false
    }

    private func sendBarkMessage(title: String, body: String) async -> Bool {
        do {
            try await barkNotifier.send(
                serverURL: barkServerURL,
                deviceKey: barkDeviceKey,
                title: title,
                body: body
            )
            statusMessage = "已发送 Bark 通知。"
            return true
        } catch BarkNotificationError.missingConfiguration {
            statusMessage = "请先填写 Bark Server URL 和 Device Key。"
        } catch BarkNotificationError.invalidServerURL {
            statusMessage = "Bark Server URL 无效。"
        } catch BarkNotificationError.apiError(let message) {
            statusMessage = "Bark 通知发送失败：\(message)"
        } catch BarkNotificationError.httpError(let statusCode) {
            statusMessage = "Bark 通知发送失败：HTTP \(statusCode)。"
        } catch {
            statusMessage = "Bark 通知发送失败。"
        }
        return false
    }

    private func barkCompanionWindow(for event: QuotaResetNotificationEvent, current: QuotaSnapshot) -> QuotaWindowSnapshot {
        switch event.kind {
        case .fiveHour:
            return current.weekly
        case .weekly:
            return current.fiveHour
        }
    }

    private var telegramNotifiedResetIDs: Set<String> {
        Set(telegramNotifiedResetIDsRaw.split(separator: "\n").map(String.init))
    }

    private var barkNotifiedResetIDs: Set<String> {
        Set(barkNotifiedResetIDsRaw.split(separator: "\n").map(String.init))
    }

    private func rememberTelegramNotifiedResetID(_ resetID: String) {
        var ids = Array(telegramNotifiedResetIDs)
        ids.append(resetID)
        telegramNotifiedResetIDsRaw = ids.suffix(50).joined(separator: "\n")
    }

    private func rememberBarkNotifiedResetID(_ resetID: String) {
        var ids = Array(barkNotifiedResetIDs)
        ids.append(resetID)
        barkNotifiedResetIDsRaw = ids.suffix(50).joined(separator: "\n")
    }

    private func startTimer() {
        timer?.invalidate()
        let interval = TimeInterval(max(1, refreshIntervalMinutes) * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh(force: false)
            }
        }
    }

    private func observeWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                await self?.refresh(force: false)
            }
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .full
        return formatter
    }()
}
