import AppKit
import Foundation
import SwiftUI

@MainActor
final class QuotaStore: ObservableObject {
    @AppStorage("refreshIntervalMinutes") var refreshIntervalMinutes = 10
    @AppStorage("displayMode") var displayModeRaw = DisplayMode.percentage.rawValue
    @AppStorage("lowThreshold") var lowThreshold = 20
    @AppStorage("source") var sourceRaw = QuotaSource.codexAuth.rawValue
    @AppStorage("didDefaultCodexAuthSource") private var didDefaultCodexAuthSource = false
    @AppStorage("manualPercent") var manualPercent = 50
    @AppStorage("manualResetAt") var manualResetAt = ""
    @AppStorage("manualNote") var manualNote = ""

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
        QuotaSource(rawValue: sourceRaw) ?? .local
    }

    var displayMode: DisplayMode {
        DisplayMode(rawValue: displayModeRaw) ?? .percentage
    }

    var level: QuotaLevel {
        guard let percent = snapshot.percentRemaining else {
            return .unknown
        }
        if percent <= 5 {
            return .critical
        }
        if percent <= lowThreshold {
            return .low
        }
        return .normal
    }

    var menuTitle: String {
        if isRefreshing {
            return "Codex ..."
        }

        switch displayMode {
        case .percentage:
            if let percent = snapshot.percentRemaining {
                return "Codex \(percent)%"
            }
            return "Codex --"
        case .shortStatus:
            return "Codex \(level.rawValue)"
        }
    }

    var menuColor: Color {
        level.color
    }

    var lastRefreshText: String {
        Self.relativeFormatter.localizedString(for: snapshot.capturedAt, relativeTo: Date())
    }

    var resetText: String {
        guard let resetAt = snapshot.resetAt else {
            return "未知"
        }
        return Self.dateFormatter.string(from: resetAt)
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

    private func makeProvider() -> QuotaProviding {
        switch source {
        case .codexAuth:
            return CodexAuthUsageProvider()
        case .local:
            return LocalCodexProvider()
        case .manual:
            return ManualProvider(
                percentRemaining: manualPercent,
                resetAt: Self.isoFormatter.date(from: manualResetAt),
                note: manualNote
            )
        }
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

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static let isoFormatter = ISO8601DateFormatter()
}
