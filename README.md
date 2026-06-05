# Codex Quota Menubar

一个 macOS 原生菜单栏小工具，用来显示 Codex 额度状态。

![Codex Quota Menubar 宣传图](docs/assets/promo.png)

## 功能

- **灵活的菜单栏显示**：支持“圆环（仅双层圆环）”与“百分比（仅文本，如 `Codex 80%`）”两种模式，可在设置中自由切换。
  - 在圆环模式下，外圈表示 5 小时额度，内圈表示周额度，高亮部分表示剩余比例。
- **直观的数据面板**：点击菜单栏图标展示下拉面板，分开展示 5 小时额度和周额度的已用、剩余百分比、当前状态与重置时间。
- **瓶颈额度高亮**：自动识别当前瓶颈额度，支持 5 小时额度与周额度并列瓶颈，并可在设置中切换判断方式。
- **可解释的瓶颈判断**：支持“按剩余百分比”和“按使用趋势”两种模式；悬停“当前瓶颈”卡片或“瓶颈”标签可查看判断依据。
- **智能刷新机制**：支持手动刷新、定时自动刷新和系统睡眠唤醒后的自动恢复刷新。
- **低额度分段提醒**：支持 10%、20%、30%、40%、50% 五档自定义低额度状态提醒。
- **Telegram 手机推送**：支持 5 小时额度和周额度重置提醒、测试消息、Keychain 保存 Bot Token，并区分到期重置、疑似服务商调整和未知恢复。
- **Bark 手机推送**：支持 Bark iOS 通知，默认使用 `https://api.day.app`，也可配置自建 Bark Server；Device Key 保存在 Keychain。
- **无签名开机自启**：支持一键开启/关闭开机自启（基于 LaunchAgent 实现，未签名的 `.app` 构建产物也可直接使用）。

## 使用步骤

### 1. 构建项目

```bash
swift build -c release
```

### 2. 运行菜单栏工具

```bash
swift run -c release CodexQuotaMenubar
```

成功标志：mac 顶部栏出现对应的圆环图标或百分比文本。如果登录态不可用或请求失败，会显示置灰状态，点击能看到失败原因。

## 开发与验证

1. 构建：

   ```bash
   swift build
   ```

2. 测试：

   ```bash
   swift test
   ```

3. 一键检查：

   ```bash
   scripts/check.sh
   ```

成功标志：命令输出没有 error，测试报告显示所有测试通过。

## 安装为 App

为了日常稳定使用与支持开机自启，推荐将其打包为 `.app` 应用：

1. **生成 `.app` 包**：

   ```bash
   scripts/build-app.sh
   ```

2. **复制到应用程序目录**：

   将生成的 `dist/Codex Quota Menubar.app` 拖入系统的 `/Applications`（应用程序）目录。

3. **运行与开机启动**：
   - 首次运行时在 `/Applications` 中**右键 -> 打开**（绕过系统未签名公证的安全提示）。
   - 打开后在设置页面勾选“开机启动”即可。

   成功标志：系统 `~/Library/LaunchAgents/` 下会生成对应的 plist 引导文件，开机后自动拉起。

## 数据源说明

当前版本固定使用 Codex 登录态数据源，会：

- 读取 `~/.codex/auth.json` 中的 ChatGPT OAuth token
- 请求 `https://chatgpt.com/backend-api/wham/usage` 获取额度使用状况
- 解析 `primary_window` 映射为 5 小时额度，将 `secondary_window` 映射为周额度
- 自动根据剩余额度切换不同颜色（正常绿色、偏低橙色、接近耗尽红色）

**风险提示**：本工具请求的 usage 接口为 ChatGPT 网页端后端接口，非 OpenAI Platform 开放接口。该接口可能随着官方网站的更新而失效，请在信任本工具的情况下使用。

如果读取失败，工具会尽量区分 `auth.json` 缺失、token 刷新失败、usage 接口 HTTP 错误或接口结构变化，并在面板中显示最近失败原因。

## Bark 推送配置

1. 在 iPhone 上安装并打开 Bark，复制 App 首页显示的 Device Key。

2. 打开本工具设置页，找到“Bark 推送”：
   - 勾选“启用 Bark 推送”。
   - `Server URL` 默认保留 `https://api.day.app`；如果你自建了 Bark Server，改成自己的服务地址。
   - 在 `Device Key` 填入 Bark App 中复制的 key；如果复制的是完整测试 URL，也可以直接粘贴，工具会自动提取其中的 key。
   - 按需开启“5 小时额度重置提醒”和“周额度重置提醒”。

3. 点击“发送测试消息”。

成功标志：iPhone 收到标题为“Codex 额度提醒”的 Bark 通知，正文包含“Bark 测试消息”。

额度重置时，Bark 通知会使用适合 iOS 通知栏阅读的纯文本样式，例如：

```text
标题：Codex 5 小时额度已重置
正文：
当前剩余：100%
周额度：61%
重置原因：到期重置
```

**风险提示**：Device Key 相当于 Bark 推送凭证，泄露后别人可以向你的设备发送通知。本工具会将 Device Key 保存到 macOS Keychain；如果使用公共 `api.day.app`，通知内容会经过 Bark 公共服务和 Apple APNs。介意隐私时建议自建 Bark Server。

## 瓶颈判断方式

设置页面的“瓶颈判断方式”提供两种模式：

- **按剩余百分比**：默认模式。直接比较 5 小时额度和周额度的剩余百分比，剩余更低的一项会被标记为瓶颈。
- **按使用趋势**：优先结合最近 30 天的周中/周末小时使用习惯预测重置前的预计消耗；历史不足或没有预测风险时，会回退到短期消耗趋势和静态支撑时间判断。

历史记录只保存在本机 `UserDefaults` 中。工具会保留最近 30 天的小时桶聚合数据，每天最多 24 个桶，只记录刷新次数、活跃次数和额度百分比下降量；不保存全量调用明细、token、prompt，也不会读取 Codex 的 `logs_2.sqlite`。
