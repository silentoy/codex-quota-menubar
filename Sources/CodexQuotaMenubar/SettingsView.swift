import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: QuotaStore

    var body: some View {
        Form {
            Section {
                branding
            }

            Section("通用") {
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

                Toggle("开机启动", isOn: launchAtLoginBinding)
            }

            Section("提醒") {
                Picker("低额度提醒", selection: $store.lowThreshold) {
                    Text("10%").tag(10)
                    Text("20%").tag(20)
                    Text("30%").tag(30)
                    Text("40%").tag(40)
                    Text("50%").tag(50)
                }
                .pickerStyle(.segmented)
            }

            Section {
                Text("通过 ~/.codex/auth.json 读取登录态数据。\n开机启动需以 .app 形式运行。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .scrollIndicators(.hidden)
        .onAppear {
            store.syncLaunchAtLoginState()
        }
    }

    // MARK: - Subviews

    private var branding: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 48, height: 48)
                } else {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.system(size: 36))
                        .foregroundStyle(.tint)
                }

                Text("Codex Quota")
                    .font(.title2.weight(.semibold))

                Text("v\(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private var launchAtLoginBinding: Binding<Bool> {
        Binding {
            store.launchAtLogin
        } set: { enabled in
            store.setLaunchAtLogin(enabled)
        }
    }

    private var thresholdColor: Color {
        if store.lowThreshold <= 10 {
            return .red
        } else if store.lowThreshold <= 30 {
            return .orange
        }
        return .green
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}
