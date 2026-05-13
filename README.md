# Codex Dashboard

A tiny native macOS menu bar dashboard that shows recent Codex usage and Codex rate-limit remaining percentages from local Codex session logs.

## What it can show

- Last 5 hours token usage from `~/.codex/**/*.jsonl`
- Last 7 days token usage from `~/.codex/**/*.jsonl`
- 5-hour and weekly Codex rate-limit remaining percentage from the latest `rate_limits` entry in local session logs
- Recent Codex sessions and latest activity time

## Important notes

ChatGPT-plan Codex limits are not exposed through a stable public API. The app reads the latest local Codex `token_count` event with a `rate_limits` payload, which is the same local data surfaced by Codex status views.

The app only reads local Codex session logs. It does not read Codex auth files, OAuth tokens, account credentials, or session secrets, and it does not upload usage data anywhere. The only external action is opening the Codex usage web page in your browser when you click the menu item.

## Build

```sh
./build.sh
```

The built app will be at:

```sh
build/codex-dashboard.app
```

Run it:

```sh
open "build/codex-dashboard.app"
```

## Package DMG

```sh
./package-dmg.sh
```

The distributable DMG will be created at:

```sh
dist/codex-dashboard-0.1.0.dmg
```
