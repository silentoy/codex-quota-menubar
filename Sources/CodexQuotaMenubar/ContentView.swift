import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: QuotaStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            detailRows
            notice
            actions
            footer
        }
        .padding(14)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Codex 额度")
                    .font(.headline)
                Text(store.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(percentText)
                .font(.title2.weight(.semibold))
                .foregroundStyle(store.menuColor)
                .monospacedDigit()
        }
    }

    private var detailRows: some View {
        VStack(spacing: 8) {
            InfoRow(label: "状态", value: store.level.rawValue, valueColor: store.menuColor)
            InfoRow(label: "预计重置", value: store.resetText)
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

    private var percentText: String {
        guard let percent = store.snapshot.percentRemaining else {
            return "--"
        }
        return "\(percent)%"
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
