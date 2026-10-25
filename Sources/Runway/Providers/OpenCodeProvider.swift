import Foundation

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
    static func authURL(dataHome: String? = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]) -> URL {
        let base = dataHome?.nonBlank.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share")
        return base.appendingPathComponent("opencode/auth.json")
    }

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

            var usageWindow: UsageWindow? {
                let normalizedStatus = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                // The status is authoritative: rate-limited means exhausted whatever the percent says.
                if normalizedStatus == "rate-limited" || normalizedStatus == "rate_limited" {
                    return UsageWindow(usedPercent: 100, resetsAt: ISO8601Timestamp.date(from: resetsAt))
                }
                guard normalizedStatus == nil || normalizedStatus == "ok" else { return nil }
                guard let percent else { return nil }
                return UsageWindow(usedPercent: percent, resetsAt: ISO8601Timestamp.date(from: resetsAt))
            }
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
            throw ProviderError.notSignedIn(cli: "opencode auth login")
        case 429:
            throw ProviderError.message("Rate limited by OpenCode. Try again shortly.")
        default:
            throw ProviderError.message("OpenCode usage error: HTTP \(code)")
        }
    }
}
