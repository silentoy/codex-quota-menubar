import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: QuotaStore

    var body: some View {
        Form {
            Section(store.t("预览", "Preview")) {
                preview
            }

            Section(store.t("通用", "General")) {
                Picker(store.t("语言", "Language"), selection: $store.appLanguageRaw) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.rawValue).tag(lang.rawValue)
                    }
                }

                Picker(store.t("刷新间隔", "Refresh Interval"), selection: $store.refreshIntervalMinutes) {
                    Text(store.t("5 分钟", "5 Minutes")).tag(5)
                    Text(store.t("10 分钟", "10 Minutes")).tag(10)
                    Text(store.t("30 分钟", "30 Minutes")).tag(30)
                }
                .onChange(of: store.refreshIntervalMinutes) {
                    store.updateTimer()
                }

                Picker(store.t("显示格式", "Display Format"), selection: $store.displayModeRaw) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.localizedName(lang: store.language)).tag(mode.rawValue)
                    }
                }

                Picker(store.t("瓶颈判断方式", "Bottleneck Assessment"), selection: $store.bottleneckModeRaw) {
                    ForEach(BottleneckMode.allCases) { mode in
                        Text(mode.localizedName(lang: store.language)).tag(mode.rawValue)
                    }
                }
                .onChange(of: store.bottleneckModeRaw) {
                    store.updateBottleneckEvaluation()
                }

                Toggle(store.t("开机启动", "Launch at Login"), isOn: launchAtLoginBinding)
            }

            Section(store.t("提醒", "Notifications")) {
                Picker(store.t("低额度提醒", "Low Quota Alert"), selection: $store.lowThreshold) {
                    Text("10%").tag(10)
                    Text("20%").tag(20)
                    Text("30%").tag(30)
                    Text("40%").tag(40)
                    Text("50%").tag(50)
                }
                .pickerStyle(.segmented)
            }

            Section(store.t("Telegram 推送", "Telegram Push")) {
                Toggle(store.t("启用 Telegram 推送", "Enable Telegram Push"), isOn: $store.telegramEnabled)

                SecureField("Bot Token", text: telegramBotTokenBinding)
                    .textContentType(.password)

                TextField("Chat ID", text: $store.telegramChatID)

                Toggle(store.t("5 小时额度重置提醒", "5-Hour Quota Reset Alert"), isOn: $store.telegramNotifyFiveHourReset)
                Toggle(store.t("周额度重置提醒", "Weekly Quota Reset Alert"), isOn: $store.telegramNotifyWeeklyReset)

                Button {
                    store.sendTelegramTestMessage()
                } label: {
                    if store.isSendingTelegramTest {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text(store.t("发送中", "Sending"))
                        }
                    } else {
                        Label(store.t("发送测试消息", "Send Test Message"), systemImage: "paperplane")
                    }
                }
                .disabled(store.isSendingTelegramTest)

                Text(store.t("Token 保存在 macOS Keychain；重置原因来自本地推断，非到期场景会标注“疑似”。", "Token is saved in macOS Keychain. Reset reasons are inferred locally; non-expiration events are marked as 'suspected'."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(store.t("Bark 推送", "Bark Push")) {
                Toggle(store.t("启用 Bark 推送", "Enable Bark Push"), isOn: $store.barkEnabled)

                TextField("Server URL", text: $store.barkServerURL)
                    .textContentType(.URL)

                SecureField("Device Key", text: barkDeviceKeyBinding)
                    .textContentType(.password)

                Toggle(store.t("5 小时额度重置提醒", "5-Hour Quota Reset Alert"), isOn: $store.barkNotifyFiveHourReset)
                Toggle(store.t("周额度重置提醒", "Weekly Quota Reset Alert"), isOn: $store.barkNotifyWeeklyReset)

                Button {
                    store.sendBarkTestMessage()
                } label: {
                    if store.isSendingBarkTest {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text(store.t("发送中", "Sending"))
                        }
                    } else {
                        Label(store.t("发送测试消息", "Send Test Message"), systemImage: "paperplane")
                    }
                }
                .disabled(store.isSendingBarkTest)

                Text(store.t("Device Key 保存在 macOS Keychain；默认使用 https://api.day.app，也可填写自建 Bark Server。", "Device Key is saved in macOS Keychain. Defaults to https://api.day.app, self-hosted Bark Server is also supported."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Text(store.t("通过 ~/.codex/auth.json 读取登录态数据。\n开机启动需以 .app 形式运行。", "Reads auth data from ~/.codex/auth.json.\nAuto launch requires running as a .app."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .scrollIndicators(.hidden)
        .onAppear {
            store.syncLaunchAtLoginState()
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows
                .filter(\.canBecomeKey)
                .forEach { $0.makeKeyAndOrderFront(nil) }
        }
    }

    // MARK: - Subviews

    private var preview: some View {
        HStack(spacing: 12) {
            previewBadge

            VStack(alignment: .leading, spacing: 4) {
                Text(store.t("菜单栏显示", "Menu Bar Display"))
                    .font(.subheadline.weight(.semibold))

                Text(store.t("低于 \(store.lowThreshold)% 时显示橙色提醒，5% 以下显示红色。", "Alert is orange when below \(store.lowThreshold)%, and red when below 5%."))
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
            Text(store.t("Codex 18%", "Codex 18%"))
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

    private var barkDeviceKeyBinding: Binding<String> {
        Binding {
            store.barkDeviceKey
        } set: { deviceKey in
            store.saveBarkDeviceKey(deviceKey)
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
