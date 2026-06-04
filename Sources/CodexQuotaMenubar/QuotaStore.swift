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

    @Published private(set) var snapshot: QuotaSnapshot = .unknown(
        source: .codexAuth,
        detail: "等待首次刷新。"
    )
    @Published private(set) var isRefreshing = false
    @Published private(set) var statusMessage = "等待首次刷新。"

    private var timer: Timer?
    private var lastManualRefreshAt: Date?

    init() {
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
        dateText(snapshot.resetAt)
    }

    var bottleneckText: String {
        snapshot.bottleneck?.rawValue ?? "未知"
    }

    func level(for percent: Int?) -> QuotaLevel {
        guard let percent else { return .unknown }
        if percent <= 5 {
            return .critical
        }
        if percent <= lowThreshold {
            return .low
        }
        return .normal
    }

    func percentText(_ percent: Int?) -> String {
        percent.map { "\($0)%" } ?? "未知"
    }

    func resetText(for window: QuotaWindowSnapshot) -> String {
        dateText(window.resetAt)
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

        if result.failed, snapshot.percentRemaining != nil, !force {
            statusMessage = "读取失败，显示上次结果。"
        } else {
            snapshot = result
            if result.failed {
                statusMessage = "读取失败。"
            } else if result.percentRemaining == nil {
                statusMessage = "未读取到额度。"
            } else {
                statusMessage = "刚刚更新。"
            }
        }

        isRefreshing = false
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

    private func dateText(_ date: Date?) -> String {
        guard let date else {
            return "未知"
        }
        if Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date()) {
            return Self.sameYearDateFormatter.string(from: date)
        }
        return Self.crossYearDateFormatter.string(from: date)
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

    private static let sameYearDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()

    private static let crossYearDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/M/d HH:mm"
        return formatter
    }()

    private static let isoFormatter = ISO8601DateFormatter()
}
