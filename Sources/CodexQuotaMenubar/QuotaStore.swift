import AppKit
import Foundation
import SwiftUI

@MainActor
final class QuotaStore: ObservableObject {
    @AppStorage("refreshIntervalMinutes") var refreshIntervalMinutes = 10 {
        willSet { objectWillChange.send() }
    }
    @AppStorage("adaptiveFrequency") var adaptiveFrequency = false {
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
    @AppStorage("quotaUsageHourBuckets") private var quotaUsageHourBucketsRaw = "" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("quotaUsageLastSample") private var quotaUsageLastSampleRaw = "" {
        willSet { objectWillChange.send() }
    }
    static var defaultLanguageRaw: String {
        if let preferred = Locale.preferredLanguages.first, preferred.hasPrefix("en") {
            return AppLanguage.en.rawValue
        }
        return AppLanguage.zh.rawValue
    }

    @AppStorage("appLanguage") var appLanguageRaw = QuotaStore.defaultLanguageRaw {
        willSet { objectWillChange.send() }
    }

    var language: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .zh
    }

    func t(_ zh: String, _ en: String) -> String {
        language == .en ? en : zh
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
    @Published private(set) var resetCredits: ResetCreditsState = .loading
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
        let initialMsg = appLanguageRaw == AppLanguage.en.rawValue ? "Waiting for first refresh." : "等待首次刷新。"
        statusMessage = initialMsg
        snapshot = .unknown(
            source: .codexAuth,
            detail: initialMsg
        )
        bottleneckEvaluation = QuotaBottleneckEvaluator.evaluate(
            snapshot: .unknown(
                source: .codexAuth,
                detail: initialMsg
            ),
            historyRecords: [],
            mode: .percentage
        )
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

    var relativeFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: language == .en ? "en_US" : "zh_CN")
        formatter.unitsStyle = .full
        return formatter
    }

    var nextRefreshText: String {
        guard snapshot.percentRemaining != nil else {
            return t("等待刷新", "Waiting to refresh")
        }
        let nextDate = snapshot.capturedAt.addingTimeInterval(TimeInterval(currentRefreshIntervalMinutes * 60))
        let diff = nextDate.timeIntervalSinceNow
        if diff <= 0 {
            return t("即将刷新", "Refreshing soon")
        }
        let minutes = Int(ceil(diff / 60.0))
        if minutes <= 0 {
            return t("即将刷新", "Refreshing soon")
        }
        return t("\(minutes)分钟后", "In \(minutes) min\(minutes > 1 ? "s" : "")")
    }

    var resetText: String {
        QuotaResetDateFormatter.text(for: bottleneckEvaluation.resetAt, kind: bottleneck ?? .fiveHour, lang: language)
    }

    var bottleneckWindows: [QuotaWindowKind] {
        bottleneckEvaluation.windows
    }

    var bottleneck: QuotaWindowKind? {
        bottleneckWindows.count == 1 ? bottleneckWindows.first : nil
    }

    var bottleneckText: String {
        if bottleneckWindows.count > 1 {
            return t("并列瓶颈", "Multiple Bottlenecks")
        }
        return bottleneck?.localizedName(lang: language) ?? t("未知", "Unknown")
    }

    var bottleneckExplanation: String {
        bottleneckEvaluation.explanation
    }

    var bottleneckSummaryText: String {
        guard let percent = bottleneckEvaluation.remainingPercent else {
            return t("暂未读取到精确额度。", "No accurate quota read yet.")
        }
        return t(
            "\(bottleneckText) · 剩余 \(percent)% · \(resetText)",
            "\(bottleneckText) · \(percent)% remaining · \(resetText)"
        )
    }

    func level(for percent: Int?) -> QuotaLevel {
        QuotaLevel.classify(percent: percent, lowThreshold: lowThreshold)
    }

    func percentText(_ percent: Int?) -> String {
        percent.map { "\($0)%" } ?? t("未知", "Unknown")
    }

    func resetText(for window: QuotaWindowSnapshot) -> String {
        QuotaResetDateFormatter.text(for: window.resetAt, kind: window.kind, lang: language)
    }

    var resetCreditsCountText: String {
        switch resetCredits {
        case .loading:
            return "--"
        case .failed:
            return "--"
        case .loaded(let snapshot):
            return t("\(snapshot.availableCount) 次", "\(snapshot.availableCount)")
        }
    }

    var resetCreditsSubtitleText: String {
        switch resetCredits {
        case .loading:
            return t("正在读取", "Loading")
        case .failed:
            return t("读取失败", "Unavailable")
        case .loaded(let snapshot):
            guard snapshot.availableCount > 0 else {
                return t("暂无可用重置", "No available resets")
            }
            guard let expiresAt = snapshot.earliestAvailableExpiration else {
                return t("最近过期时间未知", "Earliest expiry unknown")
            }
            return t(
                "最近 \(resetCreditDateText(expiresAt)) 过期",
                "Earliest \(resetCreditDateText(expiresAt))"
            )
        }
    }

    func resetCreditDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .en ? "en_US" : "zh_CN")
        formatter.calendar = .current
        formatter.timeZone = .current
        formatter.dateFormat = language == .en ? "MMM d HH:mm" : "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    func resetCreditRelativeExpirationText(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    func accessibilityLabel() -> String {
        let fiveHourLevel = level(for: snapshot.fiveHour.percentRemaining).localizedName(lang: language)
        let weeklyLevel = level(for: snapshot.weekly.percentRemaining).localizedName(lang: language)
        return t(
            "Codex 额度，5 小时\(fiveHourLevel)，周额度\(weeklyLevel)",
            "Codex Quota, 5-Hour \(fiveHourLevel), Weekly \(weeklyLevel)"
        )
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
            statusMessage = t("刷新太频繁，请稍等。", "Refresh too frequent. Please wait.")
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
        statusMessage = t("正在刷新...", "Refreshing...")

        let provider = makeProvider()
        let fetchResult = await provider.fetchAll()
        let result = fetchResult.usage
        let previousSnapshot = snapshot

        if result.failed, snapshot.percentRemaining != nil, !force {
            statusMessage = t("读取失败，显示上次结果。", "Fetch failed. Showing last result.")
        } else {
            snapshot = result
            rememberHistoryIfNeeded(result)
            rememberUsageFrequencyIfNeeded(result)
            updateBottleneckEvaluation()
            if result.failed {
                statusMessage = t("读取失败。", "Fetch failed.")
            } else if result.percentRemaining == nil {
                statusMessage = t("未读取到额度。", "No quota read.")
            } else {
                statusMessage = t("刚刚更新。", "Just updated.")
            }
        }

        if !result.failed {
            await sendQuotaResetNotifications(previous: previousSnapshot, current: result)
        }

        applyResetCreditsResult(fetchResult.resetCredits)

        isRefreshing = false
        if !result.failed, adaptiveFrequency {
            updateTimer()
        }
    }

    func saveTelegramBotToken(_ token: String) {
        telegramBotToken = token
        do {
            try KeychainTokenStore.saveTelegramBotToken(token)
        } catch {
            statusMessage = t("保存 Telegram Token 失败。", "Failed to save Telegram Token.")
        }
    }

    func saveBarkDeviceKey(_ deviceKey: String) {
        barkDeviceKey = deviceKey
        do {
            try KeychainTokenStore.saveBarkDeviceKey(deviceKey)
        } catch {
            statusMessage = t("保存 Bark Device Key 失败。", "Failed to save Bark Device Key.")
        }
    }

    func sendTelegramTestMessage() {
        guard !isSendingTelegramTest else { return }
        isSendingTelegramTest = true
        Task {
            _ = await sendTelegramMessage(t("Codex 额度 Telegram 测试消息。", "Codex Quota Telegram test message."))
            isSendingTelegramTest = false
        }
    }

    func sendBarkTestMessage() {
        guard !isSendingBarkTest else { return }
        isSendingBarkTest = true
        Task {
            _ = await sendBarkMessage(
                title: t("Codex 额度提醒", "Codex Quota Alert"),
                body: t("Bark 测试消息\n如果你看到这条通知，说明推送已配置成功。", "Bark test message\nIf you see this notification, the push is configured successfully.")
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
                statusMessage = t("开机启动需以 .app 形式运行。", "Auto launch requires running as a .app.")
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
                statusMessage = t("已开启开机启动。", "Auto launch enabled.")
            } else {
                launchAtLogin = false
                statusMessage = t("写入 LaunchAgent 失败。", "Failed to write LaunchAgent.")
            }
        } else {
            try? fm.removeItem(atPath: plistPath)
            launchAtLogin = false
            statusMessage = t("已关闭开机启动。", "Auto launch disabled.")
        }
    }

    private var launchAgentLabel: String {
        "com.qihui.codex-quota-menubar"
    }

    private var launchAgentPlistPath: String {
        let home = NSHomeDirectory()
        return "\(home)/Library/LaunchAgents/\(launchAgentLabel).plist"
    }

    private func makeProvider() -> CodexAuthUsageProvider {
        // 固定使用 Codex 登录态 provider
        CodexAuthUsageProvider()
    }

    private func applyResetCreditsResult(_ result: ResetCreditsState) {
        switch result {
        case .loaded, .loading:
            resetCredits = result
        case .failed:
            if case .loaded = resetCredits {
                return
            }
            resetCredits = result
        }
    }

    var historyData: [QuotaHistoryRecord] {
        historyRecords
    }

    var usageBuckets: [QuotaUsageHourBucket] {
        usageHourBuckets
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

    private var usageHourBuckets: [QuotaUsageHourBucket] {
        get {
            guard let data = quotaUsageHourBucketsRaw.data(using: .utf8),
                  let buckets = try? JSONDecoder().decode([QuotaUsageHourBucket].self, from: data) else {
                return []
            }
            return buckets
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let raw = String(data: data, encoding: .utf8) else {
                return
            }
            quotaUsageHourBucketsRaw = raw
        }
    }

    private var usageLastSample: QuotaUsageLastSample? {
        get {
            guard let data = quotaUsageLastSampleRaw.data(using: .utf8) else {
                return nil
            }
            return try? JSONDecoder().decode(QuotaUsageLastSample.self, from: data)
        }
        set {
            guard let newValue,
                  let data = try? JSONEncoder().encode(newValue),
                  let raw = String(data: data, encoding: .utf8) else {
                quotaUsageLastSampleRaw = ""
                return
            }
            quotaUsageLastSampleRaw = raw
        }
    }

    private func rememberUsageFrequencyIfNeeded(_ snapshot: QuotaSnapshot) {
        var buckets = usageHourBuckets
        var lastSample = usageLastSample
        QuotaUsageFrequencyRecorder.record(
            snapshot: snapshot,
            buckets: &buckets,
            lastSample: &lastSample
        )
        usageHourBuckets = buckets
        usageLastSample = lastSample
    }

    func updateBottleneckEvaluation() {
        bottleneckEvaluation = QuotaBottleneckEvaluator.evaluate(
            snapshot: snapshot,
            historyRecords: historyRecords,
            usageBuckets: usageHourBuckets,
            mode: bottleneckMode,
            lang: language
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
            lang: language,
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
            lang: language,
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
            statusMessage = t("已发送 Telegram 通知。", "Telegram notification sent.")
            return true
        } catch TelegramNotificationError.missingConfiguration {
            statusMessage = t("请先填写 Telegram Token 和 Chat ID。", "Please configure Telegram Token and Chat ID first.")
        } catch {
            statusMessage = t("Telegram 通知发送失败。", "Failed to send Telegram notification.")
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
            statusMessage = t("已发送 Bark 通知。", "Bark notification sent.")
            return true
        } catch BarkNotificationError.missingConfiguration {
            statusMessage = t("请先填写 Bark Server URL 和 Device Key。", "Please configure Bark Server URL and Device Key first.")
        } catch BarkNotificationError.invalidServerURL {
            statusMessage = t("Bark Server URL 无效。", "Invalid Bark Server URL.")
        } catch BarkNotificationError.apiError(let message) {
            statusMessage = t("Bark 通知发送失败：\(message)", "Failed to send Bark notification: \(message)")
        } catch BarkNotificationError.httpError(let statusCode) {
            statusMessage = t("Bark 通知发送失败：HTTP \(statusCode)。", "Failed to send Bark notification: HTTP \(statusCode).")
        } catch {
            statusMessage = t("Bark 通知发送失败。", "Failed to send Bark notification.")
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

    var currentRefreshIntervalMinutes: Int {
        if adaptiveFrequency {
            return calculateAdaptiveInterval()
        } else {
            return refreshIntervalMinutes
        }
    }

    private func calculateAdaptiveInterval() -> Int {
        // 规则 1：当额度完全耗尽 (bottleneck <= 0) 且未到重置时间时，锁定为 20 分钟以省流
        if let bottleneckPercent = snapshot.percentRemaining, bottleneckPercent <= 0 {
            if let resetAt = snapshot.resetAt, Date() < resetAt {
                return 20
            }
        }
        
        // 分别获取 5 小时额度和周额度的剩余百分比（nil 时默认 100）
        let fiveHourPercent = snapshot.fiveHour.percentRemaining ?? 100
        let weeklyPercent = snapshot.weekly.percentRemaining ?? 100
        
        let maxBurnRate = max(
            QuotaBottleneckEvaluator.calculateBurnRate(windowKind: .fiveHour, snapshot: snapshot, historyRecords: historyRecords, duration: 3600),
            QuotaBottleneckEvaluator.calculateBurnRate(windowKind: .weekly, snapshot: snapshot, historyRecords: historyRecords, duration: 3600)
        )
        
        // 规则 2：极度高危期（5 小时额度 <= 5%）-> 3 分钟
        if fiveHourPercent <= 5 { return 3 }
        
        // 规则 3：高危活跃期（5 小时额度 <= 20%，或最近一小时有明显的消耗流速 > 5.0%/hour）-> 5 分钟
        if fiveHourPercent <= 20 || maxBurnRate > 5.0 { return 5 }
        
        // 规则 4：正常监控期（5 小时额度 <= 50%，或周额度已低于 20% 警戒线）-> 10 分钟
        if fiveHourPercent <= 50 || weeklyPercent <= 20 { return 10 }
        
        // 规则 5：充足闲置期（5 小时 > 50%，且周额度 > 20% 且无消耗）-> 20 分钟
        return 20
    }

    private func startTimer() {
        timer?.invalidate()
        let interval = TimeInterval(max(1, currentRefreshIntervalMinutes) * 60)
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

    #if DEBUG
    func setSnapshotForTesting(_ snapshot: QuotaSnapshot) {
        self.snapshot = snapshot
    }

    func setResetCreditsForTesting(_ resetCredits: ResetCreditsState) {
        self.resetCredits = resetCredits
    }
    #endif
}
