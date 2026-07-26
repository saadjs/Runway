import Foundation

/// Claude Code usage via the OAuth usage endpoint. Runway reuses whatever
/// credentials it can find, in priority order:
///
///   1. the `claude` CLI's login-keychain item ("Claude Code-credentials"),
///   2. the CLI's `~/.claude/.credentials.json` fallback file,
///   3. the **Claude macOS app**'s encrypted token cache in its Application
///      Support `config.json` (so Runway works even when the CLI isn't set up).
///
/// The account-level usage endpoint returns the same 5-hour / 7-day windows
/// regardless of which of these tokens is used, so any valid one works. We try
/// them in order and fall through to the next on a 401, which also covers the
/// case where the CLI's stored token is present but stale.
///
/// We deliberately do NOT refresh Claude tokens ourselves: the CLI and the
/// desktop app both rotate their refresh tokens, so refreshing here could
/// invalidate the user's real login. When every candidate is expired we surface
/// a "run `claude`" (or "open the Claude app") hint instead.
struct ClaudeProvider: UsageProvider {
    let id = "claude"
    let displayName = "Claude"
    let shortCode = "CL"
    let logoResource = "claude"

    private static let keychainService = "Claude Code-credentials"
    private static let cache = CredentialCache()

    func fetchUsage() async throws -> ProviderUsage {
        let cliCandidates = await Self.cache.current(loader: { Self.loadCLICandidates() })
        var lastError: Error = ProviderError.tokenExpired(cli: "claude")
        var attemptedTokens = Set<String>()

        for creds in cliCandidates {
            attemptedTokens.insert(creds.accessToken)
            if creds.isExpired {
                lastError = ProviderError.tokenExpired(cli: "claude")
                continue
            }
            do {
                let usage = try await ClaudeUsageAPI.fetch(accessToken: creds.accessToken)
                return ProviderUsage(
                    fiveHour: usage.fiveHour?.usageWindow,
                    weekly: usage.sevenDay?.usageWindow,
                    planLabel: creds.planLabel)
            } catch {
                guard Self.allowsCredentialFallback(after: error) else {
                    // A rate limit, network failure, or server error is not evidence
                    // that the credential is bad. Surface it without touching the
                    // desktop safe-storage keychain item.
                    throw error
                }
                lastError = error
                continue
            }
        }

        // Reading the Claude app's safe-storage password can show a keychain
        // prompt. Only touch it when every higher-priority CLI credential is
        // unavailable, expired, or rejected by the usage endpoint.
        let candidates = await Self.cache.includingDesktopFallback(
            primaryCandidates: cliCandidates,
            loader: { ClaudeDesktopCredentials.load() })
        guard !candidates.isEmpty else { throw ProviderError.notSignedIn(cli: "claude") }

        for creds in candidates where attemptedTokens.insert(creds.accessToken).inserted {
            if creds.isExpired {
                lastError = ProviderError.tokenExpired(cli: "claude")
                continue
            }
            do {
                let usage = try await ClaudeUsageAPI.fetch(accessToken: creds.accessToken)
                return ProviderUsage(
                    fiveHour: usage.fiveHour?.usageWindow,
                    weekly: usage.sevenDay?.usageWindow,
                    planLabel: creds.planLabel)
            } catch {
                guard Self.allowsCredentialFallback(after: error) else { throw error }
                lastError = error
                continue
            }
        }
        throw lastError
    }

    // MARK: - Credentials

    struct Credentials: Sendable {
        let accessToken: String
        let expiresAt: Date?
        let planLabel: String?

        var isExpired: Bool {
            // Unknown expiry: assume valid and let a 401 surface real expiry,
            // rather than rejecting a usable token (and bypassing the cache) outright.
            guard let expiresAt else { return false }
            return Date() >= expiresAt
        }
    }

    /// Gathers the CLI credential sources in priority order, de-duped by token.
    /// The desktop app is deliberately excluded because reading its safe-storage
    /// key can prompt; `fetchUsage()` loads it lazily only if these candidates fail.
    private static func loadCLICandidates() -> [Credentials] {
        var result: [Credentials] = []
        var seenTokens = Set<String>()
        func add(_ creds: Credentials?) {
            guard let creds, seenTokens.insert(creds.accessToken).inserted else { return }
            result.append(creds)
        }

        // 1 & 2: the `claude` CLI (keychain via the non-prompting `security` CLI,
        // then the direct Security.framework read, then the fallback file).
        //
        // The direct read is the one that can trigger a keychain prompt, so we only
        // fall to it when the `security` CLI path yields nothing parseable — never
        // when it already succeeded (see `Keychain` and the CLAUDE.md gotcha).
        if let creds = Keychain.readGenericPasswordViaSecurityCLI(service: keychainService)
            .flatMap({ try? parse($0) }) {
            add(creds)
        } else if let data = Keychain.readGenericPassword(service: keychainService) {
            add(try? parse(data))
        }
        let fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: fileURL) {
            add(try? parse(data))
        }

        return result
    }

    private static func parse(_ data: Data) throws -> Credentials {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { throw ProviderError.message("Could not parse Claude credentials.") }

        let expiresAt = (oauth["expiresAt"] as? Double).map {
            Date(timeIntervalSince1970: $0 / 1000)
        }
        let plan = (oauth["subscriptionType"] as? String).map(Self.prettyPlan)
        return Credentials(accessToken: token, expiresAt: expiresAt, planLabel: plan)
    }

    static func prettyPlan(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func allowsCredentialFallback(after error: Error) -> Bool {
        if case ProviderError.tokenExpired = error { return true }
        return false
    }
}

/// In-memory credential cache shared across refreshes so each poll doesn't spawn
/// a `security` subprocess (or, on the desktop-app path, re-trigger a keychain
/// prompt / re-run the AES decrypt).
actor CredentialCache {
    private var cached: [ClaudeProvider.Credentials]?
    private var validUntil: Date?
    private var includesDesktopFallback = false

    func current(loader: @Sendable () -> [ClaudeProvider.Credentials]) async
        -> [ClaudeProvider.Credentials]
    {
        if isValid, let cached {
            return cached
        }
        let fresh = loader()
        store(fresh, includesDesktopFallback: false)
        return fresh
    }

    func includingDesktopFallback(
        primaryCandidates: [ClaudeProvider.Credentials],
        loader: @Sendable () -> [ClaudeProvider.Credentials]
    ) async -> [ClaudeProvider.Credentials] {
        if isValid, includesDesktopFallback, let cached {
            return cached
        }

        let primary = isValid ? (cached ?? primaryCandidates) : primaryCandidates
        let desktop = loader()
        var seenTokens = Set<String>()
        let combined = (primary + desktop).filter {
            seenTokens.insert($0.accessToken).inserted
        }

        // Do not remember a failed fallback lookup. A manual refresh immediately
        // after the user signs in must check the credential sources again.
        if desktop.isEmpty {
            if primary.isEmpty {
                clear()
            }
            return combined
        }

        store(combined, includesDesktopFallback: true)
        return combined
    }

    private var isValid: Bool {
        guard cached != nil, let validUntil else { return false }
        return Date() < validUntil
    }

    private func store(
        _ fresh: [ClaudeProvider.Credentials],
        includesDesktopFallback: Bool
    ) {
        guard !fresh.isEmpty else {
            clear()
            return
        }

        let now = Date()
        let potentiallyUsable = fresh.filter {
            $0.expiresAt.map { $0 > now } ?? true
        }
        guard !potentiallyUsable.isEmpty else {
            // An expired-only result should be reloaded on the next refresh so a
            // newly rotated CLI credential is picked up immediately.
            clear()
            return
        }

        cached = fresh
        self.includesDesktopFallback = includesDesktopFallback

        // Expired candidates must not shorten the lifetime of a usable fallback.
        // Re-read a little before the soonest future expiry; if none is known,
        // use a short TTL to avoid repeated subprocesses and keychain prompts.
        let soonestUnexpired = potentiallyUsable.compactMap(\.expiresAt).min()
        validUntil = soonestUnexpired?.addingTimeInterval(-60)
            ?? now.addingTimeInterval(5 * 60)
    }

    private func clear() {
        cached = nil
        validUntil = nil
        includesDesktopFallback = false
    }
}

// MARK: - Claude macOS app token cache

/// Reads the Claude desktop app's OAuth token out of its Electron `safeStorage`
/// blob in `~/Library/Application Support/Claude/config.json`.
///
/// The blob decrypts to a dictionary keyed by `<account>:<org>:<host>:<scopes>:`;
/// we want the entry carrying the `claude_code` scope (the same token kind the
/// CLI uses for the usage endpoint). Reading the "Claude Safe Storage" keychain
/// password prompts the user once — Runway isn't on that item's ACL — and an
/// "Always Allow" binds to Runway's code signature.
enum ClaudeDesktopCredentials {
    private static let safeStorageService = "Claude Safe Storage"

    static func load() -> [ClaudeProvider.Credentials] {
        guard let blob = tokenCacheBlob() else { return [] }
        guard let password = safeStoragePassword(),
              let plaintext = ElectronSafeStorage.decrypt(base64: blob, password: password),
              let root = try? JSONSerialization.jsonObject(with: plaintext) as? [String: Any]
        else { return [] }
        return credentials(from: root)
    }

    private static func configURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/config.json")
    }

    /// The newer `oauth:tokenCacheV2` is preferred; the older key is a fallback.
    private static func tokenCacheBlob() -> String? {
        guard let data = try? Data(contentsOf: configURL()),
              let cfg = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return (cfg["oauth:tokenCacheV2"] as? String) ?? (cfg["oauth:tokenCache"] as? String)
    }

    /// The desktop app didn't store this item through `/usr/bin/security`, so the
    /// CLI read would need a prompt (which the 2s-timeout helper would dismiss).
    /// Go straight to the direct read, which shows a real, grantable prompt.
    private static func safeStoragePassword() -> String? {
        Keychain.readGenericPassword(service: safeStorageService)
            .flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Extract usable credentials from the decrypted cache, preferring the
    /// `claude_code`-scoped entry and, among matches, the one that expires latest.
    private static func credentials(from root: [String: Any]) -> [ClaudeProvider.Credentials] {
        let entries = root.compactMap { key, value -> (isClaudeCode: Bool, creds: ClaudeProvider.Credentials)? in
            guard let entry = value as? [String: Any],
                  let token = entry["token"] as? String, !token.isEmpty
            else { return nil }
            let expiresAt = (entry["expiresAt"] as? Double).map {
                Date(timeIntervalSince1970: $0 / 1000)
            }
            let plan = (entry["subscriptionType"] as? String).map(ClaudeProvider.prettyPlan)
            let creds = ClaudeProvider.Credentials(
                accessToken: token, expiresAt: expiresAt, planLabel: plan)
            return (key.contains("claude_code"), creds)
        }

        // claude_code-scoped tokens first, latest-expiring within each group.
        return entries
            .sorted { lhs, rhs in
                if lhs.isClaudeCode != rhs.isClaudeCode { return lhs.isClaudeCode }
                let l = lhs.creds.expiresAt ?? .distantPast
                let r = rhs.creds.expiresAt ?? .distantPast
                return l > r
            }
            .map(\.creds)
    }
}

// MARK: - OAuth usage endpoint

private enum ClaudeUsageAPI {
    private static let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    struct Response: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }

        struct Window: Decodable {
            let utilization: Double?
            let resetsAt: String?

            enum CodingKeys: String, CodingKey {
                case utilization
                case resetsAt = "resets_at"
            }

            /// Map this window to the shared `UsageWindow` model.
            var usageWindow: UsageWindow? {
                guard let used = utilization else { return nil }
                return UsageWindow(usedPercent: used, resetsAt: Response.parseDate(resetsAt))
            }
        }

        private static func parseDate(_ string: String?) -> Date? {
            guard let string else { return nil }
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: string) ?? {
                f.formatOptions = [.withInternetDateTime]
                return f.date(from: string)
            }()
        }
    }

    static func fetch(accessToken: String) async throws -> Response {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200:
            return try JSONDecoder().decode(Response.self, from: data)
        case 401:
            throw ProviderError.tokenExpired(cli: "claude")
        case 429:
            throw ProviderError.message("Rate limited by Anthropic. Try again shortly.")
        default:
            throw ProviderError.message("Claude usage error: HTTP \(code)")
        }
    }
}
