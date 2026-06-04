import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: QuotaStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            quotaSections
            summaryRows
            notice
            actions
            footer
        }
        .padding(14)
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
                level: store.level(for: store.snapshot.fiveHour.percentRemaining),
                usedText: store.percentText(store.snapshot.fiveHour.percentUsed),
                remainingText: store.percentText(store.snapshot.fiveHour.percentRemaining),
                resetText: store.resetText(for: store.snapshot.fiveHour)
            )
            QuotaWindowView(
                window: store.snapshot.weekly,
                level: store.level(for: store.snapshot.weekly.percentRemaining),
                usedText: store.percentText(store.snapshot.weekly.percentUsed),
                remainingText: store.percentText(store.snapshot.weekly.percentRemaining),
                resetText: store.resetText(for: store.snapshot.weekly)
            )
        }
    }

    private var summaryRows: some View {
        VStack(spacing: 8) {
            InfoRow(label: "当前瓶颈", value: store.bottleneckText, valueColor: store.menuColor)
            InfoRow(label: "最后刷新", value: store.lastRefreshText)
            InfoRow(label: "数据来源", value: store.snapshot.source.rawValue)
        }
    }

    @ViewBuilder
    private var notice: some View {
        if store.level == .low || store.level == .critical || store.snapshot.percentRemaining == nil {
            Text(noticeText)
                .font(.caption)
                .foregroundStyle(store.menuColor)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(store.menuColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var actions: some View {
        HStack {
            Button {
                store.manualRefresh()
            } label: {
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("刷新")
                }
            }

            Button("打开 Codex") {
                store.openCodex()
            }

            Button("设置") {
                openSettings()
            }

            Spacer()
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
}

private struct QuotaWindowView: View {
    let window: QuotaWindowSnapshot
    let level: QuotaLevel
    let usedText: String
    let remainingText: String
    let resetText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(window.kind.rawValue)
                    .font(.subheadline.weight(.semibold))
                Spacer()
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
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
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
