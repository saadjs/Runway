import Foundation

/// OpenCode Go usage, reusing the API key the `opencode` CLI stores in its
/// `auth.json` under the `opencode-go` provider entry.
///
/// Unlike Claude and Codex this is a long-lived API key, not an OAuth token, so
/// there is nothing to refresh: a rejected key means the subscription is gone or
/// the key was rotated, and the fix is to sign in again in the CLI.
struct OpenCodeProvider: UsageProvider {
    let id = "opencode"
    let displayName = "opencode"
    let shortCode = "OC"
    let logoResource = "opencode"

    func fetchUsage() async throws -> ProviderUsage {
        let key = try OpenCodeAuth.loadAPIKey()
        return try await OpenCodeUsageAPI.fetch(apiKey: key).providerUsage
    }
}

// MARK: - auth.json

enum OpenCodeAuth {
    /// The CLI's own credential store, honouring the XDG override it respects.
    static func authURL(dataHome: String? = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]) -> URL {
        let base = dataHome?.nonBlank.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share")
        return base.appendingPathComponent("opencode/auth.json")
    }

    /// Process environment and default location first; only if both come up empty
    /// do we pay for a login shell, which is the sole way a launchd-started app
    /// sees `XDG_DATA_HOME`/`OPENCODE_API_KEY` set in the user's profile.
    static func loadAPIKey() throws -> String {
        if let env = ProcessInfo.processInfo.environment["OPENCODE_API_KEY"]?.nonBlank { return env }
        if let key = apiKey(at: authURL()) { return key }
        if let shellHome = LoginShellEnv.value("XDG_DATA_HOME"),
           let key = apiKey(at: authURL(dataHome: shellHome)) {
            return key
        }
        if let key = LoginShellEnv.value("OPENCODE_API_KEY") { return key }
        throw ProviderError.notSignedIn(cli: "opencode auth login")
    }

    private static func apiKey(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return apiKey(fromAuthJSON: data)
    }

    /// `{ "opencode-go": { "type": "api", "key": "sk-…" } }`
    static func apiKey(fromAuthJSON data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = root["opencode-go"] as? [String: Any],
              let key = (entry["key"] as? String)?.nonBlank
        else { return nil }
        return key
    }
}

// MARK: - zen/go usage endpoint

enum OpenCodeUsageAPI {
    private static let url = URL(string: "https://opencode.ai/zen/go/v1/usage")!

    struct Response: Decodable {
        let usage: Usage?

        /// Go's limits are the 5-hour ("rolling"), weekly, and monthly dollar caps.
        var providerUsage: ProviderUsage {
            ProviderUsage(
                fiveHour: usage?.rolling?.usageWindow,
                weekly: usage?.weekly?.usageWindow,
                monthly: usage?.monthly?.usageWindow,
                planLabel: "Go")
        }

        struct Usage: Decodable {
            let rolling: Window?
            let weekly: Window?
            let monthly: Window?
        }

        struct Window: Decodable {
            let status: String?
            let percent: Double?
            let resetsAt: String?

            /// Map this window to the shared `UsageWindow` model. `rate-limited`
            /// means the window is exhausted even though it is not `ok`; the API's
            /// percent is normally 100, but the status is authoritative here.
            /// Other non-OK statuses are dropped because their percent is not a
            /// usable reading.
            var usageWindow: UsageWindow? {
                let normalizedStatus = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if normalizedStatus == "rate-limited" || normalizedStatus == "rate_limited" {
                    return UsageWindow(usedPercent: 100, resetsAt: Response.parseDate(resetsAt))
                }
                guard normalizedStatus == nil || normalizedStatus == "ok" else { return nil }
                guard let percent else { return nil }
                return UsageWindow(usedPercent: percent, resetsAt: Response.parseDate(resetsAt))
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

    static func fetch(apiKey: String) async throws -> Response {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("Runway", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200...299:
            return try JSONDecoder().decode(Response.self, from: data)
        case 401, 403:
            // A static key is never refreshed, so this means revoked or rotated.
            throw ProviderError.notSignedIn(cli: "opencode auth login")
        case 429:
            throw ProviderError.message("Rate limited by OpenCode. Try again shortly.")
        default:
            throw ProviderError.message("OpenCode usage error: HTTP \(code)")
        }
    }
}
