# Reset Credits Panel Design

## Goal

Show Codex rate-limit reset credits in the menu bar panel without competing with the existing 5-hour and weekly quota cards.

The user should be able to see:

- How many reset credits are currently available.
- Which available credit expires first.
- Per-credit `status`, `title`, `granted_at`, and `expires_at` after expanding the section.

## Placement

Add a new collapsible drawer below the two quota window cards and above the existing summary rows.

The drawer should follow the existing "Quota Trend" interaction pattern:

- One clickable header row.
- A chevron that rotates when expanded.
- A subtle divider between header and body.
- Body content appears only when expanded.
- The whole section uses the existing glass card styling.

## Collapsed State

The collapsed header should be readable at a glance:

- Left icon: reset/refresh-style symbol.
- Title: `重置次数` / `Reset Credits`.
- Subtitle: earliest expiration, for example `最近 7月18日 08:34 过期`.
- Right value: available count, for example `2 次` / `2`.
- Chevron on the far right.

If no available credits exist, show:

- Value: `0 次`.
- Subtitle: `暂无可用重置` / `No available resets`.
- Use secondary text color, not warning color.

## Expanded State

Each credit appears as a compact list item:

- First row:
  - `title` as the primary text.
  - `status` as a small right-aligned pill.
- Second area:
  - `获得` / `Granted`: local-time `granted_at`.
  - `过期` / `Expires`: local-time `expires_at`.

The earliest expiring available credit may use the low-quota warm color for its expiration row and include a relative hint, for example `18 天后`.

Do not show IDs, tokens, cookies, account identifiers, or raw response payloads.

## Data Rules

Use the `rate-limit-reset-credits` endpoint only when the current data source is Codex auth.

The provider should:

- Read `tokens.access_token` from `~/.codex/auth.json`.
- Refresh the token with `tokens.refresh_token` when the access token is expired, following the existing usage provider pattern.
- Send `Authorization: Bearer <access_token>`.
- Send `ChatGPT-Account-Id` when the account ID can be derived by the existing logic.
- Decode only `available_count` and the credit fields needed by the panel.

All displayed dates must be converted from UTC to local time.

## Error Handling

If reset credits fail to load but quota usage succeeds:

- Keep the main quota panel usable.
- Show the drawer header with a secondary state such as `读取失败` / `Unavailable`.
- Put the short error explanation in help text or expanded body.

If the endpoint returns HTTP 401:

- Treat it as expired credentials or missing `Authorization` header.
- Reuse the existing auth failure tone; do not expose sensitive headers or tokens.

If the endpoint response shape changes:

- Show `读取失败` for reset credits only.
- Do not mark the quota usage snapshot as failed unless the usage endpoint also failed.

## Interaction

The drawer is collapsed by default.

Clicking the header toggles expansion with the same animation curve used by `chartSection`.

Manual refresh should refresh both quota usage and reset credits together. The drawer should show existing cached reset credit data until the new request finishes, unless there has never been a successful reset-credit fetch.

## Localization

Support both existing app languages:

- Chinese labels: `重置次数`, `最近过期`, `获得`, `过期`, `暂无可用重置`, `读取失败`.
- English labels: `Reset Credits`, `Earliest Expiry`, `Granted`, `Expires`, `No available resets`, `Unavailable`.

## Testing

Add focused tests for:

- Decoding `available_count` and credit list fields.
- Local time formatting for `granted_at` and `expires_at`.
- Earliest available expiration selection.
- 401 error mapping.
- Main quota usage remains usable when reset credits fail.

