import Foundation

/// Codex usage via the ChatGPT backend, reusing the credentials the `codex` CLI
/// stores in `~/.codex/auth.json`. On a 401 we refresh the OAuth token and write
/// the rotated tokens back to `auth.json` (matching what the CLI itself does), so
/// the CLI and Runway stay in sync.
struct CodexProvider: UsageProvider {
    let id = "codex"
    let displayName = "Codex"
    let shortCode = "CX"
    let logoResource = "codex"

    func fetchUsage() async throws -> ProviderUsage {
        var creds = try CodexAuth.load()
        do {
            return try await Self.fetch(with: creds)
        } catch ProviderError.tokenExpired {
            // Refresh once, persist, retry.
            creds = try await CodexAuth.refresh(creds)
            return try await Self.fetch(with: creds)
        }
    }

    private static func fetch(with creds: CodexAuth.Credentials) async throws -> ProviderUsage {
        let usage = try await CodexUsageAPI.fetch(
            accessToken: creds.accessToken,
            accountId: creds.accountId)
        return ProviderUsage(
            fiveHour: usage.rateLimit?.primaryWindow?.usageWindow,
            weekly: usage.rateLimit?.secondaryWindow?.usageWindow,
            planLabel: usage.planType?.capitalized)
    }
}

// MARK: - auth.json

enum CodexAuth {
    struct Credentials: Sendable {
        var accessToken: String
        var refreshToken: String
        var accountId: String?
    }

    static func homeURL() -> URL {
        if let dir = ProcessInfo.processInfo.environment["CODEX_HOME"],
           !dir.trimmingCharacters(in: .whitespaces).isEmpty {
            return URL(fileURLWithPath: dir)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    static func authURL() -> URL { homeURL().appendingPathComponent("auth.json") }

    static func load() throws -> Credentials {
        let url = authURL()
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String, !access.isEmpty
        else { throw ProviderError.notSignedIn(cli: "codex") }

        let refresh = tokens["refresh_token"] as? String ?? ""
        let accountId = (tokens["account_id"] as? String) ?? accountIdFromIDToken(tokens["id_token"] as? String)
        return Credentials(accessToken: access, refreshToken: refresh, accountId: accountId)
    }

    /// Refresh via OpenAI's token endpoint, then merge the new tokens back into
    /// auth.json preserving any other keys the CLI keeps there.
    static func refresh(_ creds: Credentials) async throws -> Credentials {
        guard !creds.refreshToken.isEmpty else { throw ProviderError.tokenExpired(cli: "codex") }

        var request = URLRequest(url: URL(string: "https://auth.openai.com/oauth/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": "app_EMoamEEZ73f0CkXaXp7hrann",
            "grant_type": "refresh_token",
            "refresh_token": creds.refreshToken,
            "scope": "openid profile email",
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ProviderError.tokenExpired(cli: "codex") }

        var updated = creds
        updated.accessToken = json["access_token"] as? String ?? creds.accessToken
        updated.refreshToken = json["refresh_token"] as? String ?? creds.refreshToken
        writeBack(updated, newIDToken: json["id_token"] as? String)
        return updated
    }

    private static func writeBack(_ creds: Credentials, newIDToken: String?) {
        let url = authURL()
        var root = (try? Data(contentsOf: url))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        var tokens = root["tokens"] as? [String: Any] ?? [:]
        tokens["access_token"] = creds.accessToken
        tokens["refresh_token"] = creds.refreshToken
        if let newIDToken { tokens["id_token"] = newIDToken }
        if let accountId = creds.accountId { tokens["account_id"] = accountId }
        root["tokens"] = tokens
        root["last_refresh"] = ISO8601DateFormatter().string(from: Date())

        guard let out = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted]) else { return }
        try? out.write(to: url, options: .atomic)
    }

    /// Fallback: pull `chatgpt_account_id` from the id_token JWT claims.
    private static func accountIdFromIDToken(_ idToken: String?) -> String? {
        guard let idToken else { return nil }
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = json["https://api.openai.com/auth"] as? [String: Any]
        else { return nil }
        return auth["chatgpt_account_id"] as? String
    }
}

// MARK: - wham/usage endpoint

private enum CodexUsageAPI {
    private static let url = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    struct Response: Decodable {
        let planType: String?
        let rateLimit: RateLimit?

        enum CodingKeys: String, CodingKey {
            case planType = "plan_type"
            case rateLimit = "rate_limit"
        }

        struct RateLimit: Decodable {
            let primaryWindow: Window?
            let secondaryWindow: Window?

            enum CodingKeys: String, CodingKey {
                case primaryWindow = "primary_window"
                case secondaryWindow = "secondary_window"
            }
        }

        struct Window: Decodable {
            let usedPercent: Double?
            let resetAt: Double?

            enum CodingKeys: String, CodingKey {
                case usedPercent = "used_percent"
                case resetAt = "reset_at"
            }

            /// Map this window to the shared `UsageWindow` model.
            var usageWindow: UsageWindow? {
                guard let used = usedPercent else { return nil }
                return UsageWindow(usedPercent: used, resetsAt: resetAt.map { Date(timeIntervalSince1970: $0) })
            }
        }
    }

    static func fetch(accessToken: String, accountId: String?) async throws -> Response {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("Runway", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200...299:
            return try JSONDecoder().decode(Response.self, from: data)
        case 401, 403:
            throw ProviderError.tokenExpired(cli: "codex")
        default:
            throw ProviderError.message("Codex usage error: HTTP \(code)")
        }
    }
}
