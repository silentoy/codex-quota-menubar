# Codex Quota Menubar

一个 macOS 原生菜单栏小工具，用来显示 Codex 额度状态。

## 功能

- 顶部栏显示 `Codex ...`、`Codex 72%`、`Codex --` 等短状态
- 点击顶部栏查看剩余额度、状态、预计重置、最后刷新、数据来源
- 支持手动刷新、自动刷新和睡眠恢复刷新
- 支持 Codex 登录态、本机状态与手动填写三种数据源
- 默认读取 `~/.codex/auth.json` 并请求 ChatGPT usage 接口获取真实额度

## 使用步骤

1. 构建项目：

   ```bash
   swift build
   ```

2. 运行菜单栏工具：

   ```bash
   swift run CodexQuotaMenubar
   ```

3. 顶部栏出现 `Codex ...` 后，等待刷新完成。

成功标志：mac 顶部栏出现 `Codex <百分比>%`；如果登录态不可用或接口失败，会显示 `Codex --`，点击后能看到失败原因。

## 数据源说明

默认的 Codex 登录态模式会：

- 读取 `~/.codex/auth.json` 中的 ChatGPT OAuth token
- 请求 `https://chatgpt.com/backend-api/wham/usage`
- 解析 `primary_window` 和 `secondary_window` 的 `used_percent`
- 顶部栏显示两个窗口里更低的剩余百分比

风险提示：这个接口不是公开稳定的 OpenAI Platform API，可能随 Codex/ChatGPT 后端变更而失效；请只在你信任本工具时使用。

本机状态模式只读取少量非敏感 Codex 状态文件，例如：

- `~/.codex/.codex-global-state.json`
- `~/.codex/version.json`

如果这些文件里没有公开额度字段，工具会显示 `Codex --`，并提示未发现精确额度。

如果你想先有稳定展示效果，可以在设置里切换到“手动填写”，输入剩余百分比和预计重置时间。
