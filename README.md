# Codex Quota Menubar

一个 macOS 原生菜单栏小工具，用来显示 Codex 额度状态。

![Codex Quota Menubar 宣传图](docs/assets/promo.png)

## 功能

- 顶部栏显示纯双层圆环图标，不显示文字和百分值
- 外圈表示 5 小时额度，内圈表示周额度，圆环高亮部分表示剩余额度
- 点击顶部栏查看两个额度的剩余百分比、状态、预计重置、最后刷新、数据来源
- 支持手动刷新、自动刷新和睡眠恢复刷新
- 支持设置开机启动
- 默认读取 `~/.codex/auth.json` 并请求 ChatGPT usage 接口获取真实额度
- 支持圆环或当前瓶颈百分比两种菜单栏显示模式
- 支持瓶颈额度高亮、低额度提醒和失败原因提示

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

成功标志：mac 顶部栏出现双层圆环图标；如果登录态不可用或接口失败，会显示灰色空心双环，点击后能看到失败原因。

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

1. 生成 `.app`：

   ```bash
   scripts/build-app.sh
   ```

2. 打开构建产物：

   ```bash
   open "dist/Codex Quota Menubar.app"
   ```

3. 如果确认可用，可以把 `dist/Codex Quota Menubar.app` 拖到 `/Applications`。

成功标志：mac 顶部栏出现一个双层圆环图标；点击后能看到 5 小时额度和周额度。

说明：当前 App 未签名、未公证，只建议在自己的机器上使用。开机启动需要以 `.app` 形式运行，`swift run` 开发态下可能不可用。

## 数据源说明

当前版本固定使用 Codex 登录态数据源，会：

- 读取 `~/.codex/auth.json` 中的 ChatGPT OAuth token
- 请求 `https://chatgpt.com/backend-api/wham/usage`
- 解析 `primary_window` 和 `secondary_window` 的 `used_percent`
- 将 `primary_window` 映射为 5 小时额度
- 将 `secondary_window` 映射为周额度
- 顶部栏外圈表示 5 小时额度，内圈表示周额度，圆环高亮部分表示剩余额度

风险提示：这个接口不是公开稳定的 OpenAI Platform API，可能随 Codex/ChatGPT 后端变更而失效；请只在你信任本工具时使用。

如果读取失败，工具会尽量区分 `auth.json` 缺失、token 刷新失败、usage 接口 HTTP 错误或接口结构变化，并在面板中显示最近失败原因。
