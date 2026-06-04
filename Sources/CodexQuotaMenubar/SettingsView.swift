import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: QuotaStore

    var body: some View {
        Form {
            Picker("刷新间隔", selection: $store.refreshIntervalMinutes) {
                Text("5 分钟").tag(5)
                Text("10 分钟").tag(10)
                Text("30 分钟").tag(30)
            }
            .onChange(of: store.refreshIntervalMinutes) {
                store.updateTimer()
            }

            Picker("显示格式", selection: $store.displayModeRaw) {
                ForEach(DisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode.rawValue)
                }
            }

            Stepper(value: $store.lowThreshold, in: 1...80) {
                Text("低额度提醒：\(store.lowThreshold)%")
            }

            Picker("数据来源", selection: $store.sourceRaw) {
                ForEach(QuotaSource.allCases) { source in
                    Text(source.rawValue).tag(source.rawValue)
                }
            }
            .onChange(of: store.sourceRaw) {
                Task {
                    await store.refresh(force: true)
                }
            }

            if store.source == .manual {
                Section("手动额度") {
                    Stepper(value: $store.manualPercent, in: 0...100) {
                        Text("剩余：\(store.manualPercent)%")
                    }

                    TextField("重置时间，例如 2026-06-05T08:00:00+08:00", text: $store.manualResetAt)
                        .textFieldStyle(.roundedBorder)

                    TextField("备注", text: $store.manualNote)
                        .textFieldStyle(.roundedBorder)

                    Button("应用手动额度") {
                        Task {
                            await store.refresh(force: true)
                        }
                    }
                }
            }

            Section {
                Text("Codex 登录态模式会读取 ~/.codex/auth.json 并请求 chatgpt.com/backend-api/wham/usage；它不是公开稳定 API。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
