import Foundation

/// Claude Code usage via the OAuth usage endpoint, reusing the credentials the
/// `claude` CLI stores in the login keychain (item "Claude Code-credentials").
///
/// We deliberately do NOT refresh Claude tokens ourselves: the CLI rotates the
/// refresh token, so refreshing here could invalidate the user's `claude` login.
/// When the cached token is stale we re-read the keychain to pick up whatever the
/// CLI last refreshed; if it is still expired we surface a "run `claude`" hint.
struct ClaudeProvider: UsageProvider {
    let id = "claude"
    let displayName = "Claude"
    let shortCode = "CL"
    let logoResource = "claude"

    private static let keychainService = "Claude Code-credentials"
    private static let cache = CredentialCache()

    func fetchUsage() async throws -> ProviderUsage {
        let creds = try await Self.cache.current(loader: { try Self.loadCredentials() })
        guard !creds.isExpired else { throw ProviderError.tokenExpired(cli: "claude") }

        let usage = try await ClaudeUsageAPI.fetch(accessToken: creds.accessToken)
        return ProviderUsage(
            fiveHour: usage.fiveHour?.usageWindow,
            weekly: usage.sevenDay?.usageWindow,
            planLabel: creds.planLabel)
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

    /// Re-reads the credential source. Keychain first (macOS default), then the
    /// `~/.claude/.credentials.json` file used on some setups.
    ///
    /// The keychain is read via the `security` CLI first because that path never
    /// prompts (see `Keychain.readGenericPasswordViaSecurityCLI`); the direct
    /// Security.framework read is a prompting fallback.
    private static func loadCredentials() throws -> Credentials {
        if let data = Keychain.readGenericPasswordViaSecurityCLI(service: keychainService),
           let creds = try? parse(data) {
            return creds
        }
        if let data = Keychain.readGenericPassword(service: keychainService),
           let creds = try? parse(data) {
            return creds
        }
        let fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: fileURL), let creds = try? parse(data) {
            return creds
        }
        throw ProviderError.notSignedIn(cli: "claude")
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

    private static func prettyPlan(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

/// In-memory credential cache shared across refreshes so each poll doesn't spawn
/// a `security` subprocess (or, on the fallback path, re-trigger a keychain prompt).
private actor CredentialCache {
    private var cached: ClaudeProvider.Credentials?
    private var validUntil: Date?

    func current(loader: @Sendable () throws -> ClaudeProvider.Credentials) throws
        -> ClaudeProvider.Credentials
    {
        if let cached, let validUntil, Date() < validUntil {
            return cached
        }
        let fresh = try loader()
        cached = fresh
        // Re-read a little before real expiry; if expiry is unknown, fall back to a
        // short TTL so we still avoid a keychain prompt on every refresh.
        validUntil = fresh.expiresAt?.addingTimeInterval(-60) ?? Date().addingTimeInterval(5 * 60)
        return fresh
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
