# Runway

A minimal macOS menu-bar app that shows your **5-hour** and **weekly** usage
limits for **Claude Code** and **Codex** — nothing else. Native components,
official logos, system colors only.

<sub>macOS 13+ · SwiftUI `MenuBarExtra` · menu-bar only (no Dock icon)</sub>

## What it does

- Reads the credentials the `claude` and `codex` CLIs already store, so there's
  nothing to log into.
- Shows each provider's rolling 5-hour and 7-day windows with a percentage and a
  reset countdown.
- The menu-bar label shows the highest current 5-hour usage at a glance.
- Refreshes on launch, every 5 minutes, and on demand.

## How usage is fetched

| Provider | Credentials | Endpoint |
| --- | --- | --- |
| Claude Code | login Keychain item `Claude Code-credentials` (falls back to `~/.claude/.credentials.json`) | `GET api.anthropic.com/api/oauth/usage` |
| Codex | `~/.codex/auth.json` | `GET chatgpt.com/backend-api/wham/usage` |

Claude tokens are **not** refreshed by Runway (the CLI rotates them); if the
session is expired it asks you to run `claude`. Codex tokens are refreshed and
written back to `auth.json`, matching what the CLI does.

## Build & run

```bash
./Scripts/build-app.sh release   # builds build/Runway.app (ad-hoc signed)
open build/Runway.app
```

For development you can also just `swift run`.

> The first launch reads the Claude Keychain item; approve **Always Allow** once.
> The build is ad-hoc signed so the grant persists across launches.

## Adding another provider

The app is intentionally modular. To support a new app:

1. Add a type conforming to `UsageProvider` in `Sources/Runway/Providers/`,
   implementing `fetchUsage() -> ProviderUsage` (a `fiveHour` and `weekly`
   `UsageWindow`).
2. Drop its logo PDF in `Sources/Runway/Resources/` and reference it via
   `logoResource`.
3. Append it to `ProviderRegistry.all`.

Everything else (refresh loop, UI, menu-bar label) picks it up automatically.

## Layout

```
Sources/Runway/
  App/        RunwayApp.swift        MenuBarExtra + accessory policy
  Core/       UsageModels, UsageProvider, ProviderRegistry, Keychain
  Providers/  ClaudeProvider, CodexProvider
  Store/      UsageStore                 refresh loop + state
  Views/      MenuView, ProviderCardView, UsageBarView, Support
  Resources/  claude.pdf, codex.pdf      official logos (template-tinted)
```
