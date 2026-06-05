import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: QuotaStore

    var body: some View {
        Form {
            Section("预览") {
                preview
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

            Section("Telegram 推送") {
                Toggle("启用 Telegram 推送", isOn: $store.telegramEnabled)

                SecureField("Bot Token", text: telegramBotTokenBinding)
                    .textContentType(.password)

                TextField("Chat ID", text: $store.telegramChatID)

                Toggle("5 小时额度重置提醒", isOn: $store.telegramNotifyFiveHourReset)
                Toggle("周额度重置提醒", isOn: $store.telegramNotifyWeeklyReset)

                Button {
                    store.sendTelegramTestMessage()
                } label: {
                    if store.isSendingTelegramTest {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("发送中")
                        }
                    } else {
                        Label("发送测试消息", systemImage: "paperplane")
                    }
                }
                .disabled(store.isSendingTelegramTest)

                Text("Token 保存在 macOS Keychain；重置原因来自本地推断，非到期场景会标注“疑似”。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

    private var preview: some View {
        HStack(spacing: 12) {
            previewBadge

            VStack(alignment: .leading, spacing: 4) {
                Text("菜单栏显示")
                    .font(.subheadline.weight(.semibold))

                Text("低于 \(store.lowThreshold)% 时显示橙色提醒，5% 以下显示红色。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(thresholdColor.opacity(0.22), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var previewBadge: some View {
        if store.displayMode == .ring {
            QuotaRingsIcon(
                snapshot: previewSnapshot,
                lowThreshold: store.lowThreshold,
                isRefreshing: false,
                style: .menuBar
            )
            .frame(width: 28, height: 28)
            .padding(6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        } else {
            Text("Codex 18%")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(previewLevelColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Helpers

    private var launchAtLoginBinding: Binding<Bool> {
        Binding {
            store.launchAtLogin
        } set: { enabled in
            store.setLaunchAtLogin(enabled)
        }
    }

    private var telegramBotTokenBinding: Binding<String> {
        Binding {
            store.telegramBotToken
        } set: { token in
            store.saveTelegramBotToken(token)
        }
    }

    private var thresholdColor: Color {
        .quotaLow
    }

    private var previewLevelColor: Color {
        QuotaLevel.classify(percent: 18, lowThreshold: store.lowThreshold).color
    }

    private var previewSnapshot: QuotaSnapshot {
        QuotaSnapshot(
            fiveHour: QuotaWindowSnapshot(kind: .fiveHour, percentRemaining: 18, resetAt: nil),
            weekly: QuotaWindowSnapshot(kind: .weekly, percentRemaining: 61, resetAt: nil),
            source: .codexAuth,
            detail: "",
            capturedAt: Date(),
            failed: false
        )
    }

}
