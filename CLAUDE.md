# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Runway is a minimal macOS menu-bar app showing **5-hour** and **weekly** usage limits for **Claude Code** and **Codex** only. SwiftPM executable, macOS 13+, SwiftUI `MenuBarExtra`, menu-bar only (no Dock icon).

## Commands

```bash
swift build                        # debug build (fast compile check)
swift run                          # run unbundled for dev (shows in Dock; resources via Bundle.module)
./Scripts/build-app.sh release     # build the real menu-bar app -> build/Runway.app (ad-hoc signed)
open build/Runway.app          # launch it
./Scripts/make-icon.sh             # regenerate Assets/AppIcon.icns from the gauge.with.needle SF Symbol
```

There is **no test target** and no linter configured. Verify changes by building the app and observing it in the menu bar (the popover is driven via System Events for screenshots during development).

## Architecture

Data flows: **provider -> store -> views + menu-bar label**.

- **`Core/UsageProvider`** — the protocol every monitored app implements (`id`, `displayName`, `shortCode`, `logoResource`, `fetchUsage() async throws -> ProviderUsage`). `ProviderUsage` holds a `fiveHour` and `weekly` `UsageWindow` (each a 0–100 `usedPercent` + optional `resetsAt`). Both providers normalize to this shape.
- **`Core/ProviderRegistry.all`** — the single list of active providers. This is the modularity seam.
- **`Store/UsageStore`** (`@MainActor`, `.shared`) — owns `[providerID: ProviderState]`, fetches all providers concurrently in a `TaskGroup`, and drives refreshes. Started from `AppDelegate.applicationDidFinishLaunching`, not from a view's `onAppear`. The refresh cadence comes from `AppSettings` (re-scheduled live via a Combine subscription).
- **`Store/AppSettings`** (`@MainActor`, `.shared`) — user preferences persisted in `UserDefaults`: refresh interval, reset-countdown visibility, per-provider show/hide, and launch-at-login (backed by `SMAppService.mainApp`, not UserDefaults). Single source of truth read by the views and `UsageStore`.
- **`Views/`** — `MenuView` (popover) -> `ProviderCardView` (a native `GroupBox` per provider) -> `UsageBarView` (a native `ProgressView`). `SettingsView` is a separate `Window` scene (id `SettingsWindow.id`), opened from the popover gear button via `openWindow` + `NSApp.activate` — **not** the SwiftUI `Settings` scene, which can't be reliably opened from a MenuBarExtra/LSUIElement app.

### Settings / launch-at-login caveat

Launch-at-login (`SMAppService.mainApp.register()`) only works from the **bundled, signed** app, ideally in `/Applications`; it throws when run via `swift run`. `AppSettings.setLaunchAtLogin` swallows the error and re-reads the real status, so the toggle just stays off in dev.

### Adding a provider (the intended extension path)

1. New type conforming to `UsageProvider` in `Providers/`.
2. Logo PDF in `Sources/Runway/Resources/` (referenced by `logoResource`); add it to `Package.swift` `resources:`.
3. Append to `ProviderRegistry.all`.
   The refresh loop, popover, and menu-bar label pick it up automatically — **except** the menu-bar label only renders the first ~N providers explicitly (see gotcha below).

## Data sources (verified live; reuse the CLIs' own credentials)

- **Claude** (`ClaudeProvider`): reads the login Keychain item `Claude Code-credentials` (JSON under `claudeAiOauth`), falling back to `~/.claude/.credentials.json`. Usage: `GET api.anthropic.com/api/oauth/usage` with `Authorization: Bearer`, `anthropic-beta: oauth-2025-04-20`, `User-Agent: claude-code/<v>`. Response `five_hour`/`seven_day` -> `{utilization (0-100), resets_at ISO8601}`.
- **Codex** (`CodexProvider`): reads `~/.codex/auth.json` (`tokens.access_token` + `tokens.account_id`). Usage: `GET chatgpt.com/backend-api/wham/usage` with `Bearer` + `ChatGPT-Account-Id`. Response `rate_limit.primary_window`/`secondary_window` -> `{used_percent (0-100), reset_at epoch-seconds}`.

### Token refresh policy (deliberate, do not "fix")

- **Codex self-refreshes** on 401 via `auth.openai.com/oauth/token` and **writes the rotated tokens back to `auth.json`** (merging, preserving other keys) — matches what the CLI does, keeps both in sync.
- **Claude is never refreshed by Runway.** The CLI rotates its refresh token, so refreshing here could invalidate the user's `claude` login. On expiry, re-read the keychain (to pick up what the CLI refreshed) and otherwise surface a "run `claude`" hint.

## Critical gotchas

- **`MenuBarExtra` label rendering is severely limited.** It reliably renders an `Image` + one `Text` and **silently drops** additional sibling views, `ForEach`, nested stacks, and inline-Image-in-`Text`. The label is therefore drawn as a single template `NSImage` in `App/MenuBarLabel.swift` (gauge glyph + per-provider text + SF Symbol locks composited by hand). Do not try to rebuild it with SwiftUI views — it will only show the first token.
- **Keychain access requires in-memory caching.** Reading another app's keychain item prompts once ("Always Allow", bound to Runway's code signature). `ClaudeProvider`'s `CredentialCache` actor caches the token until ~expiry so refreshes don't re-prompt. The ad-hoc signature in `build-app.sh` keeps the grant stable across launches; rebuilds can re-prompt because ad-hoc cdhash changes.
- **SwiftPM resource bundle + codesign.** SwiftPM emits a flat `Runway_Runway.bundle` (no Info.plist). `build-app.sh` copies it into `Contents/Resources/`, **injects a minimal Info.plist** so codesign accepts it as a nested bundle, and signs inner-bundle-first. `Bundle.module` resolves logos from there. The `.icns` and `LSUIElement`/`CFBundleIconFile` are also assembled in `build-app.sh` (there is no committed Info.plist for the app).
- **Rate limiting.** Frequent Claude fetches hit Anthropic's rate limit (shown as "Rate limited by Anthropic"). `UsageStore.refresh(force:)` throttles non-forced refreshes (open + the configurable refresh timer) to once per 30s; only the ↻ button passes `force: true`. The shortest interval offered in Settings is 1 min, well above the 30s throttle.

## UI conventions

Native macOS look, set by the user: stock SwiftUI controls only (`GroupBox`, `ProgressView`), **no custom colors** (system accent + semantic colors), official provider logos as template-tinted PDFs. Usage bars and labels read as **used** (e.g. "100% used" = consumed, bar full). `Package.swift` pins Swift 5 language mode to avoid strict-concurrency friction.
