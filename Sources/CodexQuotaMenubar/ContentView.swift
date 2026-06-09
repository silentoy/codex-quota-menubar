import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: QuotaStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            bottleneckHero
            quotaSections
            chartSection
            summaryRows
            notice
            actions
            footer
        }
        .padding(OS27.Padding.panel)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: OS27.Radius.outer, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: OS27.Radius.outer, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(0.06), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    ))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: OS27.Radius.outer, style: .continuous)
                .stroke(LinearGradient(
                    colors: [Color.white.opacity(0.18), Color.white.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                ), lineWidth: 0.5)
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            QuotaRingsIcon(
                snapshot: store.snapshot,
                lowThreshold: store.lowThreshold,
                isRefreshing: store.isRefreshing
            )
            .frame(width: 32, height: 32)
            .shadow(color: store.menuColor.opacity(0.25), radius: 6, x: 0, y: 0)
            .shadow(color: store.menuColor.opacity(0.18), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.t("Codex 额度", "Codex Quota"))
                    .font(.headline)
                Text(localizedStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Text(store.level.localizedName(lang: store.language))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(store.menuColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    ZStack {
                        Capsule()
                            .fill(.ultraThinMaterial)
                        Capsule()
                            .fill(store.menuColor.opacity(0.10))
                    }
                )
                .overlay(
                    Capsule()
                        .stroke(store.menuColor.opacity(0.22), lineWidth: 0.5)
                )
                .overlay(
                    Capsule()
                        .stroke(LinearGradient(
                            colors: [Color.white.opacity(0.25), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ), lineWidth: 0.5)
                        .blendMode(.plusLighter)
                )
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
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(store.menuColor.opacity(0.20))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(store.menuColor.opacity(0.32), lineWidth: 0.5)
                Image(systemName: store.level == .normal ? "gauge.with.dots.needle.67percent" : "exclamationmark.triangle.fill")
                    .foregroundStyle(store.menuColor)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
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
        .padding(OS27.Padding.card)
        .heroGlass(tint: store.menuColor)
        .help(store.bottleneckExplanation)
    }

    @State private var isChartExpanded = false

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(OS27.Motion.expand) {
                    isChartExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .foregroundStyle(store.level.color)
                        .font(.system(size: 13, weight: .medium))
                    Text(store.t("额度消耗趋势", "Quota Trend"))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(isChartExpanded ? 90 : 0))
                        .foregroundStyle(.tertiary)
                }
                .padding(OS27.Padding.card)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isChartExpanded {
                Rectangle()
                    .fill(LinearGradient(
                        colors: [.clear, OS27.Stroke.hairline, OS27.Stroke.hairline, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(height: 0.5)
                    .padding(.horizontal, 12)
                QuotaChartView()
                    .padding([.horizontal, .bottom], 12)
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .glassCard(tint: store.level.color, tintOpacity: 0.02)
    }

    private var summaryRows: some View {
        VStack(spacing: 0) {
            InfoRow(label: store.t("下次刷新", "Next Refresh"), value: store.nextRefreshText)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            Rectangle()
                .fill(OS27.Stroke.hairline)
                .frame(height: 0.5)
                .padding(.leading, 14)
            InfoRow(label: store.t("数据来源", "Data Source"), value: store.snapshot.source.localizedName(lang: store.language))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        }
        .glassCard()
    }

    @ViewBuilder
    private var notice: some View {
        if store.level == .low || store.level == .critical || store.snapshot.percentRemaining == nil {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(noticeColor.opacity(0.18))
                    Image(systemName: store.level == .critical ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(noticeColor)
                }
                .frame(width: 18, height: 18)
                Text(noticeText)
                    .font(.caption)
                    .foregroundStyle(noticeColor)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassCard(tint: noticeColor, tintOpacity: 0.06, emphasized: true)
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
                            .tint(.white)
                            .frame(width: 12, height: 12)
                        Text(store.t("刷新中", "Refreshing"))
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text(store.t("刷新", "Refresh"))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(ProminentGlassButtonStyle(accentColor: store.level.color))
            .disabled(store.isRefreshing)

            Button {
                store.openCodex()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "app.badge")
                    Text("Codex")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(QuietGlassButtonStyle())
            .accessibilityLabel(store.t("打开 Codex", "Open Codex"))

            Button {
                openSettings()
                bringSettingsWindowToFront()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                    Text(store.t("设置", "Settings"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(QuietGlassButtonStyle())
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(OS27.Stroke.hairline)
                .frame(height: 0.5)
            Text(localizedDetailText)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(store.t("退出", "Quit")) {
                    store.quit()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
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
            HStack(spacing: 6) {
                Text(window.kind.localizedName(lang: store.language))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if isBottleneck {
                    Text(store.t("瓶颈", "Bottleneck"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(level.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(level.color.opacity(0.14), in: Capsule())
                        .help(helpText)
                }
                HStack(spacing: 4) {
                    Image(systemName: levelGlyph)
                        .font(.system(size: 10, weight: .bold))
                    Text(level.localizedName(lang: store.language))
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(level.color)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 6)

                    let fillWidth = max(0, min(geometry.size.width, geometry.size.width * progress))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [level.color, level.color.opacity(0.65)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: fillWidth, height: 6)
                        .overlay(
                            Capsule()
                                .stroke(LinearGradient(
                                    colors: [Color.white.opacity(0.40), Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ), lineWidth: 0.5)
                                .frame(width: fillWidth, height: 6)
                        )
                        .shadow(color: level.color.opacity(0.30), radius: 3, x: 0, y: 0)

                    if progress > 0 {
                        Circle()
                            .fill(level.color)
                            .frame(width: 4, height: 4)
                            .shadow(color: level.color.opacity(0.6), radius: 3, x: 0, y: 0)
                            .offset(x: max(0, fillWidth - 2))
                    }
                }
            }
            .frame(height: 6)
            .padding(.vertical, 1)

            HStack(alignment: .firstTextBaseline) {
                LabelValue(label: store.t("已用", "Used"), value: usedText, valueColor: level.color)
                LabelValue(label: store.t("剩余", "Rem"), value: remainingText)
                Spacer()
                LabelValue(label: store.t("重置", "Reset"), value: resetText)
            }
        }
        .padding(OS27.Padding.card)
        .padding(.leading, isBottleneck ? 4 : 0)
        .glassCard(tint: level.color, tintOpacity: isBottleneck ? 0.04 : 0, emphasized: isBottleneck)
        .overlay(alignment: .leading) {
            if isBottleneck {
                Capsule()
                    .fill(LinearGradient(
                        colors: [level.color, level.color.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(width: 3)
                    .shadow(color: level.color.opacity(0.45), radius: 4, x: 0, y: 0)
                    .padding(.vertical, 8)
            }
        }
    }

    private var progress: Double {
        Double(window.percentRemaining ?? 0) / 100
    }

    private var levelGlyph: String {
        switch level {
        case .normal: return "checkmark.circle.fill"
        case .low: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle.fill"
        }
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
                .monospacedDigit()
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
                .fontWeight(.semibold)
        }
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }
}

struct ProminentGlassButtonStyle: ButtonStyle {
    var accentColor: Color = .blue
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: OS27.Radius.button, style: .continuous)
                        .fill(LinearGradient(
                            colors: [
                                accentColor.opacity(configuration.isPressed ? 0.85 : (isHovered ? 1.05 : 1.0)),
                                accentColor.opacity(configuration.isPressed ? 0.78 : (isHovered ? 0.92 : 0.88))
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                    RoundedRectangle(cornerRadius: OS27.Radius.button, style: .continuous)
                        .stroke(LinearGradient(
                            colors: [Color.white.opacity(configuration.isPressed ? 0.20 : 0.45), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ), lineWidth: 0.5)
                        .blendMode(.plusLighter)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: OS27.Radius.button, style: .continuous)
                    .stroke(accentColor.opacity(0.55), lineWidth: 0.5)
            )
            .shadow(color: accentColor.opacity(configuration.isPressed ? 0.18 : 0.32), radius: configuration.isPressed ? 3 : 8, x: 0, y: configuration.isPressed ? 1 : 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(OS27.Motion.interactive, value: isHovered)
            .animation(OS27.Motion.interactive, value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

struct QuietGlassButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: OS27.Radius.button, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: OS27.Radius.button, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : (isHovered ? 0.08 : 0.04)))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: OS27.Radius.button, style: .continuous)
                    .stroke(Color.primary.opacity(isHovered ? 0.14 : 0.08), lineWidth: 0.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OS27.Radius.button, style: .continuous)
                    .stroke(LinearGradient(
                        colors: [Color.white.opacity(0.16), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ), lineWidth: 0.5)
                    .blendMode(.plusLighter)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(OS27.Motion.interactive, value: isHovered)
            .animation(OS27.Motion.interactive, value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

@available(*, deprecated, message: "Replaced by ProminentGlassButtonStyle / QuietGlassButtonStyle")
struct ModernActionButtonStyle: ButtonStyle {
    var isPrimary: Bool = false
    var accentColor: Color = .blue

    func makeBody(configuration: Configuration) -> some View {
        if isPrimary {
            ProminentGlassButtonStyle(accentColor: accentColor).makeBody(configuration: configuration)
        } else {
            QuietGlassButtonStyle().makeBody(configuration: configuration)
        }
    }
}
