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

| Provider    | Credentials                                                                                 | Endpoint                                 |
| ----------- | ------------------------------------------------------------------------------------------- | ---------------------------------------- |
| Claude Code | login Keychain item `Claude Code-credentials` (falls back to `~/.claude/.credentials.json`) | `GET api.anthropic.com/api/oauth/usage`  |
| Codex       | `~/.codex/auth.json`                                                                        | `GET chatgpt.com/backend-api/wham/usage` |

Claude tokens are **not** refreshed by Runway (the CLI rotates them); if the
session is expired it asks you to run `claude`. Codex tokens are refreshed and
written back to `auth.json`, matching what the CLI does.

## Install

```bash
brew install --cask saadjs/tap/runway
```

A notarized, stapled build straight from [Releases](https://github.com/saadjs/Runway/releases).

## Build & run

```bash
./Scripts/build-app.sh release   # builds build/Runway.app (ad-hoc signed)
open build/Runway.app
```

For development you can also just `swift run`.

> The first launch reads the Claude Keychain item; approve **Always Allow** once.
> The build is ad-hoc signed so the grant persists across launches.

## Current Release Process (notarized) & Homebrew

### One-time setup

Store the App Store Connect API key as a notarytool keychain profile named
`runway-notary` (the cert is already in the login keychain):

```bash
xcrun notarytool store-credentials runway-notary \
  --key <path-to-.p8-file> \
  --key-id <key-id> \
  --issuer <issuer-id>
```

### Cut a release

1. Bump the version (e.g. for `1.1`):

    ```bash
    APP_VERSION=1.1 ./Scripts/release.sh
    ```

    `release.sh` builds with the hardened runtime, Developer ID signs, submits to
    Apple's notary service, staples the ticket, zips the stapled `.app`, and
    prints the `version`/`sha256`/`url`.

2. Publish the artifact:

    ```bash
    gh release create v1.1 build/Runway-1.1.zip --repo saadjs/Runway --generate-notes
    ```

3. Bump `version` **and** `sha256` (each notarized build has a unique hash) in
   `saadjs/homebrew-tap/Casks/runway.rb`, using the values `release.sh` printed.
   Keep `dist/runway.rb` in this repo in sync.

Verify before announcing:

```bash
brew update && brew fetch --cask saadjs/tap/runway   # resolves URL + checks sha256
```

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
