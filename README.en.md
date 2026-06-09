# Codex Quota Menubar

A native macOS menubar widget to display Codex quota status.

![Codex Quota Menubar Promo](docs/assets/promo.png)

## v1.5.0 Highlights

- **New Glass Panel**: The main popover now uses an OS27 glass style with consistent cards, buttons, status badges, and progress bars.
- **Enhanced Trend Charts**: The quota trend section now supports `24h Remainder / 7d Consumption / 30d Consumption` views for short-term remaining quota and longer-term consumption.
- **Clearer Bottleneck Signal**: The current bottleneck, quota cards, status icons, and progress endpoints now share the same state color so the tightest quota window is easier to scan.
- **Chart Fix**: Fixed the square shadow artifact in the 24h remainder chart when remaining quota is high.

## Features

- **Flexible Menubar Display**: Supports "Ring (double ring)" and "Percentage (text-only, e.g., `Codex 80%`)" modes, which can be toggled in settings.
  - In ring mode, the outer ring represents the 5-hour quota and the inner ring represents the weekly quota, with highlights indicating the remaining ratio.
- **Intuitive Data Panel**: Click the menubar icon to display a popover panel showing the used and remaining percentages, current status, and reset times for both 5-hour and weekly quotas, with glass cards, hairline strokes, and state colors highlighting the important parts.
- **Bottleneck Highlighting**: Automatically identifies the current bottleneck quota (supporting multiple bottlenecks) and allows switching assessment modes in settings.
- **Explainable Bottleneck Assessment**: Supports "By Remaining %" and "By Usage Trend" modes. Hovering over the "Current Bottleneck" card or the "Bottleneck" tag shows the reasoning behind the assessment.
- **Quota Trend Charts**: Supports a 24h remaining line chart, 7d consumption bars, and 30d consumption bars, showing both 5-hour and weekly quotas.
- **Smart Refresh Mechanism**: Supports manual refresh, scheduled auto-refresh, and automatic refresh upon wake-from-sleep.
- **Low Quota Alert Levels**: Segmented low quota notifications customisable at 10%, 20%, 30%, 40%, and 50%.
- **Telegram Push Notifications**: Supports Telegram notification alerts for 5-hour and weekly quota resets, test messages, Keychain bot token storage, and distinguishes between scheduled reset, suspected provider adjustment, and unknown recovery.
- **Bark Push Notifications**: Supports iOS Bark notification alerts, defaulting to `https://api.day.app` or self-hosted Bark Server. Device Key is securely saved in macOS Keychain.
- **Auto Launch (No Codesign Required)**: Easily toggle startup at login (based on LaunchAgent, works seamlessly even with unsigned build outputs).
- **Multi-language Support (New in v1.4.1)**: Dynamically matches macOS system preferred language by default, and allows hot-swapping between Simplified Chinese and English in Settings.

## Usage Steps

### 1. Build Project

```bash
swift build -c release
```

### 2. Run Menubar Tool

```bash
swift run -c release CodexQuotaMenubar
```

Success mark: The corresponding ring icon or percentage text appears in the macOS menubar. If the login session is invalid or the request fails, the icon will appear grayed out, and clicking it will reveal the failure reason.

## Development & Verification

1. Build:

   ```bash
   swift build
   ```

2. Test:

   ```bash
   swift test
   ```

3. One-click Check:

   ```bash
   scripts/check.sh
   ```

Success mark: The command outputs no error, and the test report shows all tests passed.

## Installation as App

For daily stability and system startup support, it is recommended to package it as a `.app` application:

1. **Generate `.app` Package**:

   ```bash
   scripts/build-app.sh
   ```

2. **Copy to Applications Directory**:

   Drag the generated `dist/Codex Quota Menubar.app` into the system `/Applications` directory.

3. **Run & Auto Launch**:
   - For the first launch, **Right-click -> Open** from `/Applications` (to bypass gatekeeper warnings for unsigned applications).
   - Once opened, check "Launch at Login" in settings.

   Success mark: A plist launch description file will be generated in `~/Library/LaunchAgents/` to automatically launch the app upon boot.

## Data Source Description

The current version is fixed to use the Codex Auth data source, which will:

- Read the ChatGPT OAuth token from `~/.codex/auth.json`.
- Request `https://chatgpt.com/backend-api/wham/usage` to fetch usage status.
- Map `primary_window` to 5-hour quota and `secondary_window` to weekly quota.
- Automatically switch colors according to the remaining percentage (green for normal, orange for low, red for critical).

**Risk Warning**: The usage endpoint requested by this tool is the backend API of ChatGPT web version, rather than the public OpenAI Platform API. This interface may fail with updates to the official website. Please use it only if you trust this tool.

If the reading fails, the tool will try to distinguish among missing `auth.json`, token refresh failure, usage API HTTP error, or API structure changes, and display the recent failure reason in the panel.

## Bark Push Configuration

1. Install and open Bark on your iPhone, and copy the Device Key displayed on the App home page.

2. Open this tool's settings page and find "Bark Push":
   - Check "Enable Bark Push".
   - Keep `Server URL` as `https://api.day.app` by default (or change it to your self-hosted service address).
   - Enter the copied Bark key into `Device Key`. (If you copied the full test URL, you can paste it directly; the tool will automatically extract the key).
   - Turn on "5-Hour Quota Reset Alert" and "Weekly Quota Reset Alert" as needed.

3. Click "Send Test Message".

Success mark: Your iPhone receives a Bark notification titled "Codex Quota Alert" with the body "Bark test message".

Upon quota resets, Bark notifications will be sent in a clean plain-text layout:

```text
Title: Codex 5-Hour Quota Reset
Body:
Current Remaining: 100%
Weekly Quota: 61%
Reset Reason: Scheduled Reset
```

**Risk Warning**: The Device Key acts as the push credential. If leaked, others can send notifications to your device. This tool saves the Device Key to the macOS Keychain. If the public `api.day.app` is used, notification payloads will traverse the Bark public service and Apple APNs. If you have privacy concerns, it is recommended to self-host a Bark Server.

## Bottleneck Assessment Modes

The "Bottleneck Assessment" in settings offers two modes:

- **By Remaining %**: The default mode. Directly compares the remaining percentage of the 5-hour and weekly quotas. The one with the lower percentage remaining is marked as the bottleneck.
- **By Usage Trend**: Integrates weekday/weekend hourly usage habits of the last 30 days to predict consumption prior to reset. If there is insufficient history or no predicted risk, it falls back to short-term trends and static support duration assessments.

History is stored only in the local `UserDefaults`. The tool keeps the last 30 days of hourly aggregated data, up to 24 buckets per day, recording only refresh counts, active usage counts, and quota percentage drops; it does not save full request payloads, tokens, prompts, nor does it read Codex's local database.
