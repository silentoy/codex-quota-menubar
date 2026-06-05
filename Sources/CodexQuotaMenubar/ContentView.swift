import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: QuotaStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            bottleneckHero
            quotaSections
            summaryRows
            notice
            actions
            footer
        }
        .padding(14)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack {
            QuotaRingsIcon(
                snapshot: store.snapshot,
                lowThreshold: store.lowThreshold,
                isRefreshing: store.isRefreshing
            )
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(store.t("Codex 额度", "Codex Quota"))
                    .font(.headline)
                Text(localizedStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(store.level.localizedName(lang: store.language))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(store.menuColor)
        }
    }

    private var quotaSections: some View {
        VStack(spacing: 10) {
            QuotaWindowView(
                window: store.snapshot.fiveHour,
                isBottleneck: store.bottleneckWindows.contains(.fiveHour),
                level: store.level(for: store.snapshot.fiveHour.percentRemaining),
                usedText: store.percentText(store.snapshot.fiveHour.percentUsed),
                remainingText: store.percentText(store.snapshot.fiveHour.percentRemaining),
                resetText: store.resetText(for: store.snapshot.fiveHour),
                helpText: store.bottleneckExplanation
            )
            QuotaWindowView(
                window: store.snapshot.weekly,
                isBottleneck: store.bottleneckWindows.contains(.weekly),
                level: store.level(for: store.snapshot.weekly.percentRemaining),
                usedText: store.percentText(store.snapshot.weekly.percentUsed),
                remainingText: store.percentText(store.snapshot.weekly.percentRemaining),
                resetText: store.resetText(for: store.snapshot.weekly),
                helpText: store.bottleneckExplanation
            )
        }
    }

    private var bottleneckHero: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: store.level == .normal ? "gauge.with.dots.needle.67percent" : "exclamationmark.triangle.fill")
                .foregroundStyle(store.menuColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(store.t("当前瓶颈", "Current Bottleneck"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(store.bottleneckMode.localizedName(lang: store.language))
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.58))
                }
                Text(store.bottleneckSummaryText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(store.menuColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(store.menuColor.opacity(0.22), lineWidth: 1)
        )
        .help(store.bottleneckExplanation)
    }

    private var summaryRows: some View {
        VStack(spacing: 8) {
            InfoRow(label: store.t("最后刷新", "Last Refresh"), value: store.lastRefreshText)
            InfoRow(label: store.t("数据来源", "Data Source"), value: store.snapshot.source.localizedName(lang: store.language))
        }
    }

    @ViewBuilder
    private var notice: some View {
        if store.level == .low || store.level == .critical || store.snapshot.percentRemaining == nil {
            Text(noticeText)
                .font(.caption)
                .foregroundStyle(noticeColor)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(noticeColor.opacity(0.24), lineWidth: 1)
                )
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                store.manualRefresh()
            } label: {
                if store.isRefreshing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(store.level.color)
                            .frame(width: 13, height: 13)
                        Text(store.t("刷新中", "Refreshing"))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(store.level.color)
                        Text(store.t("刷新", "Refresh"))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
                }
            }
            .controlSize(.regular)
            .disabled(store.isRefreshing)
            .frame(maxWidth: .infinity)

            Button {
                store.openCodex()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "app.badge")
                    Text("Codex")
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
            }
            .controlSize(.regular)
            .accessibilityLabel(store.t("打开 Codex", "Open Codex"))
            .frame(maxWidth: .infinity)

            Button {
                openSettings()
                bringSettingsWindowToFront()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                    Text(store.t("设置", "Settings"))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
            }
            .controlSize(.regular)
            .frame(maxWidth: .infinity)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text(localizedDetailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(store.t("退出", "Quit")) {
                    store.quit()
                }
                .keyboardShortcut("q")
            }
        }
    }

    private var localizedStatusMessage: String {
        let msg = store.statusMessage
        if msg == "刚刚更新。" || msg == "Just updated." {
            return store.t("刚刚更新。", "Just updated.")
        }
        if msg == "正在刷新..." || msg == "Refreshing..." {
            return store.t("正在刷新...", "Refreshing...")
        }
        if msg == "等待首次刷新。" || msg == "Waiting for first refresh." || msg == "Waiting for the first refresh." {
            return store.t("等待首次刷新。", "Waiting for the first refresh.")
        }
        if msg == "读取失败。" || msg == "Fetch failed." {
            return store.t("读取失败。", "Fetch failed.")
        }
        if msg == "未读取到额度。" || msg == "No quota read." {
            return store.t("未读取到额度。", "No quota read.")
        }
        if msg == "读取失败，显示上次结果。" || msg == "Fetch failed. Showing last result." {
            return store.t("读取失败，显示上次结果。", "Fetch failed. Showing last result.")
        }
        if msg == "刷新太频繁，请稍等。" || msg == "Refresh too frequent. Please wait." {
            return store.t("刷新太频繁，请稍等。", "Refresh too frequent. Please wait.")
        }
        return msg
    }

    private var localizedDetailText: String {
        let detail = store.snapshot.detail
        if store.language == .en {
            var text = detail
            text = text.replacingOccurrences(of: "通过 ~/.codex/auth.json 调用 ChatGPT usage 接口。计划：", with: "Called ChatGPT usage API via ~/.codex/auth.json. Plan: ")
            text = text.replacingOccurrences(of: "，短周期剩余：", with: ", 5h remaining: ")
            text = text.replacingOccurrences(of: "，周额度剩余：", with: ", weekly remaining: ")
            text = text.replacingOccurrences(of: "ChatGPT usage 接口结构可能已变化，未读取到 primary_window 或 secondary_window。计划：", with: "ChatGPT usage API structure might have changed, primary_window or secondary_window not found. Plan: ")
            text = text.replacingOccurrences(of: "读取 Codex 登录态失败：", with: "Failed to read Codex auth: ")
            text = text.replacingOccurrences(of: "未找到 ~/.codex 目录。", with: "Directory ~/.codex not found.")
            text = text.replacingOccurrences(of: "使用手动填写的额度。", with: "Using manually entered quota.")
            text = text.replacingOccurrences(of: "从 ", with: "Read from ")
            text = text.replacingOccurrences(of: " 的 ", with: "'s ")
            text = text.replacingOccurrences(of: " 字段读取。", with: " field.")
            text = text.replacingOccurrences(of: "本机 Codex 状态中未发现公开额度字段；未读取 auth.json、Cookie 或网页登录态。", with: "No public quota fields found in local Codex state; auth.json, cookie, or web session not read.")
            text = text.replacingOccurrences(of: "等待首次刷新。", with: "Waiting for the first refresh.")
            return text
        }
        return detail
    }

    private var noticeText: String {
        if store.level == .critical {
            return store.t("额度可能已接近耗尽。", "Quota might be running out soon.")
        }
        if store.level == .low {
            return store.t("额度偏低，建议留意后续任务。", "Low quota, pay attention to subsequent tasks.")
        }
        return store.t("暂未读取到精确额度。", "No accurate quota read yet.")
    }

    private var noticeColor: Color {
        if store.snapshot.failed {
            return .quotaCritical
        }
        if store.snapshot.percentRemaining == nil {
            return .secondary
        }
        return store.menuColor
    }

    private func bringSettingsWindowToFront() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows
                .filter(\.canBecomeKey)
                .forEach { $0.makeKeyAndOrderFront(nil) }
        }
    }
}

private struct QuotaWindowView: View {
    @EnvironmentObject private var store: QuotaStore
    let window: QuotaWindowSnapshot
    let isBottleneck: Bool
    let level: QuotaLevel
    let usedText: String
    let remainingText: String
    let resetText: String
    let helpText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(window.kind.localizedName(lang: store.language))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if isBottleneck {
                    Text(store.t("瓶颈", "Bottleneck"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(level.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(level.color.opacity(0.12), in: Capsule())
                        .help(helpText)
                }
                Text(level.localizedName(lang: store.language))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(level.color)
            }

            ProgressView(value: progress)
                .tint(level.color)

            HStack(alignment: .firstTextBaseline) {
                LabelValue(label: store.t("已用", "Used"), value: usedText, valueColor: level.color)
                LabelValue(label: store.t("剩余", "Rem"), value: remainingText)
                Spacer()
                LabelValue(label: store.t("重置", "Reset"), value: resetText)
            }
        }
        .padding(10)
        .padding(.leading, isBottleneck ? 4 : 0)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(level.color)
                .frame(width: isBottleneck ? 3 : 0)
                .clipShape(Capsule())
                .padding(.vertical, 8)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(level.color.opacity(isBottleneck ? 0.32 : 0.12), lineWidth: 1)
        )
    }

    private var progress: Double {
        Double(window.percentRemaining ?? 0) / 100
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

private struct LabelValue: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(valueColor)
                .monospacedDigit()
        }
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }
}
