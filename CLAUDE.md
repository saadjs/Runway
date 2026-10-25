# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Runway is a minimal macOS menu-bar app showing **5-hour**, **weekly**, and (where the provider has one) **monthly** usage limits for **Claude Code**, **Codex**, and **OpenCode Go** only. SwiftPM executable, macOS 13+, SwiftUI `MenuBarExtra`, menu-bar only (no Dock icon).

## Commands

```bash
swift build                        # debug build (fast compile check)
swift test                         # credential/cache regression tests
swift run                          # run unbundled for dev (shows in Dock; resource bundle found beside the executable)
./Scripts/build-app.sh release     # build the real menu-bar app -> build/Runway.app (ad-hoc signed)
open build/Runway.app          # launch it
./Scripts/make-icon.sh             # regenerate Assets/AppIcon.icns from the gauge.with.needle SF Symbol
```

There is no linter configured. Run `swift test`, then verify app-facing changes by
building the bundle and observing it in the menu bar. Open the popover with a real
mouse click (a CGEvent posted at the item's position, from System Events' `position`
of `menu bar item 1 of menu bar 2`); System Events' `click`/`AXPress` don't open a
`MenuBarExtra` window. Capture with `screencapture -R` around the item.

## Architecture

Data flows: **provider -> store -> views + menu-bar label**.

- **`Core/UsageProvider`** — the protocol every monitored app implements (`id`, `displayName`, `shortCode`, `logoResource`, `fetchUsage() async throws -> ProviderUsage`). `ProviderUsage` holds a `fiveHour`, `weekly`, and optional `monthly` `UsageWindow` (each a 0–100 `usedPercent` + optional `resetsAt`). Every provider normalizes to this shape; a nil window is simply not drawn, so only OpenCode Go shows a third bar.
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
- **OpenCode Go** (`OpenCodeProvider`): reads the `opencode` CLI's `~/.local/share/opencode/auth.json` (`opencode-go.key`, honouring `XDG_DATA_HOME`), or `OPENCODE_API_KEY`. Usage: `GET opencode.ai/zen/go/v1/usage` with `Authorization: Bearer`. Response `usage.rolling`/`weekly`/`monthly` -> `{percent (0-100), resetsAt ISO8601}`. Go's limits are dollar caps ($12 per 5 h, $30 weekly, $60 monthly), so `rolling` is the 5-hour window and Go is the only provider that fills `ProviderUsage.monthly`.

### Token refresh policy (deliberate, do not "fix")

- **Codex self-refreshes** on 401 via `auth.openai.com/oauth/token` and **writes the rotated tokens back to `auth.json`** (merging, preserving other keys) — matches what the CLI does, keeps both in sync.
- **OpenCode Go has nothing to refresh** — it's a long-lived API key, so a 401 means revoked/rotated and Runway asks the user to run `opencode auth login`.
- **Claude is never refreshed by Runway.** The CLI rotates its refresh token, so refreshing here could invalidate the user's `claude` login. On expiry, re-read the keychain (to pick up what the CLI refreshed) and otherwise surface a "run `claude`" hint.

## Critical gotchas

- **`MenuBarExtra` label rendering is severely limited.** It reliably renders an `Image` + one `Text` and **silently drops** additional sibling views, `ForEach`, nested stacks, and inline-Image-in-`Text`. The label is therefore drawn as a single template `NSImage` in `App/MenuBarLabel.swift` (gauge glyph + per-provider text + SF Symbol locks composited by hand). Do not try to rebuild it with SwiftUI views — it will only show the first token. The label is re-evaluated on every store change, so `MenuBarLabel.image` returns the cached image unless the tokens or menu-bar font size changed; it draws via a drawing handler (not the deprecated `lockFocus`) so the cached image stays sharp at any display scale.
- **Keychain reads go through the `security` CLI to avoid prompts.** The `claude` CLI stores `Claude Code-credentials` via `/usr/bin/security`, so that binary is on the item's ACL and `Keychain.readGenericPasswordViaSecurityCLI` (a `security find-generic-password -w` subprocess, 2s timeout) reads it with **no prompt ever** — surviving token rotation (which rewrites the item and resets its ACL, wiping any "Always Allow" granted to Runway) and ad-hoc re-signs. The direct `SecItemCopyMatching` read is only a fallback and is the path that prompts. `ClaudeProvider`'s `CredentialCache` actor still caches in memory so polls don't spawn a subprocess each time. The cache is keyed on `credentialsVersion()` (the keychain item's modification date, read via an attributes-only `SecItemCopyMatching` that needs no ACL access, plus `.credentials.json`'s mtime and a hash of the desktop app's encrypted token blob), so a `/login` to another account is picked up on the next poll. Without that, the previous account's still-valid token kept reporting its usage until it expired. Don't key on the desktop `config.json` mtime: the app rewrites that file constantly for UI state.
- **SwiftPM resource bundle + codesign.** `build-app.sh` copies `Runway_Runway.bundle` into `Contents/Resources/` and signs inner-bundle-first. Older SwiftPM emits it flat with no Info.plist, so the script **injects a minimal one** at the bundle root; Swift 6.4+ emits a standard `Contents/` layout, where the plist goes in `Contents/` only if missing — a root Info.plist there is unsealed content codesign rejects. Logos are **not** loaded via `Bundle.module` (its accessor `fatalError`s in a packaged app because it only looks at the bundle root); `Logo` in `Views/Support.swift` locates the bundle by hand and caches each image. The `.icns` and `LSUIElement`/`CFBundleIconFile` are also assembled in `build-app.sh` (there is no committed Info.plist for the app).
- **Rate limiting.** Frequent Claude fetches hit Anthropic's rate limit (shown as "Rate limited by Anthropic"). `UsageStore.refresh(force:)` throttles non-forced refreshes (open + the configurable refresh timer) to once per 30s; only the ↻ button passes `force: true`. The shortest interval offered in Settings is 1 min, well above the 30s throttle.

## UI conventions

Native macOS look, set by the user: stock SwiftUI controls only (`GroupBox`, `ProgressView`), **no custom colors** (system accent + semantic colors), official provider logos as template-tinted PDFs. Usage bars and labels read as **used** (e.g. "100% used" = consumed, bar full). `Package.swift` pins Swift 5 language mode to avoid strict-concurrency friction.
