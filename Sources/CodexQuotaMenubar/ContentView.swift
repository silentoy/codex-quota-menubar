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
                Text("Codex 额度")
                    .font(.headline)
                Text(store.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(store.level.rawValue)
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
                    Text("当前瓶颈")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(store.bottleneckMode.rawValue)
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
            InfoRow(label: "最后刷新", value: store.lastRefreshText)
            InfoRow(label: "数据来源", value: store.snapshot.source.rawValue)
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
                    HStack(spacing: 5) {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 13, height: 13)
                        Text("刷新中")
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label("刷新", systemImage: "arrow.clockwise")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
            }
            .controlSize(.regular)
            .disabled(store.isRefreshing)
            .frame(maxWidth: .infinity)

            Button {
                store.openCodex()
            } label: {
                Label("Codex", systemImage: "app.badge")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.regular)
            .accessibilityLabel("打开 Codex")
            .frame(maxWidth: .infinity)

            Button {
                openSettings()
                bringSettingsWindowToFront()
            } label: {
                Label("设置", systemImage: "gearshape")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.regular)
            .frame(maxWidth: .infinity)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text(store.snapshot.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("退出") {
                    store.quit()
                }
                .keyboardShortcut("q")
            }
        }
    }

    private var noticeText: String {
        if store.level == .critical {
            return "额度可能已接近耗尽。"
        }
        if store.level == .low {
            return "额度偏低，建议留意后续任务。"
        }
        return "暂未读取到精确额度。"
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
                Text(window.kind.rawValue)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if isBottleneck {
                    Text("瓶颈")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(level.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(level.color.opacity(0.12), in: Capsule())
                        .help(helpText)
                }
                Text(level.rawValue)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(level.color)
            }

            ProgressView(value: progress)
                .tint(level.color)

            HStack(alignment: .firstTextBaseline) {
                LabelValue(label: "已用", value: usedText, valueColor: level.color)
                LabelValue(label: "剩余", value: remainingText)
                Spacer()
                LabelValue(label: "重置", value: resetText)
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
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(valueColor)
                .monospacedDigit()
        }
        .font(.caption)
    }
}
