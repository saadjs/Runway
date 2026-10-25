import Foundation

/// Never refreshes tokens: the CLI and desktop app rotate refresh tokens, so refreshing here could sign the user out.
struct ClaudeProvider: UsageProvider {
    let id = "claude"
    let displayName = "Claude"
    let shortCode = "CL"
    let logoResource = "claude"

    private static let keychainService = "Claude Code-credentials"
    private static let cache = CredentialCache()

    func fetchUsage() async throws -> ProviderUsage {
        let cliCandidates = await Self.cache.current(
            sourceVersion: Self.credentialsVersion(),
            loader: { Self.loadCLICandidates() })
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
                    throw error
                }
                lastError = error
                continue
            }
        }

        // Reading the desktop app's safe-storage password can prompt, so only after every CLI credential failed.
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
            guard let expiresAt else { return false }
            return Date() >= expiresAt
        }
    }

    private static func loadCLICandidates() -> [Credentials] {
        var result: [Credentials] = []
        var seenTokens = Set<String>()
        func add(_ creds: Credentials?) {
            guard let creds, seenTokens.insert(creds.accessToken).inserted else { return }
            result.append(creds)
        }

        if let creds = Keychain.readGenericPasswordViaSecurityCLI(service: keychainService)
            .flatMap({ try? parse($0) }) {
            add(creds)
        } else if let data = Keychain.readGenericPassword(service: keychainService) {
            add(try? parse(data))
        }
        if let data = try? Data(contentsOf: credentialsFileURL) {
            add(try? parse(data))
        }

        return result
    }

    private static var credentialsFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
    }

    /// Changes on re-login so another account's still-valid token isn't kept. Keyed on the desktop token blob,
    /// not `config.json`'s mtime, which churns with UI state.
    private static func credentialsVersion() -> String {
        let dates = [
            Keychain.modificationDate(service: keychainService),
            modificationDate(of: credentialsFileURL),
        ]
        .map { $0.map { "\($0.timeIntervalSince1970)" } ?? "-" }
        let desktop = ClaudeDesktopCredentials.tokenCacheBlob().map { "\($0.hashValue)" } ?? "-"
        return (dates + [desktop]).joined(separator: "|")
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate]
            as? Date
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

actor CredentialCache {
    private var cached: [ClaudeProvider.Credentials]?
    private var validUntil: Date?
    private var includesDesktopFallback = false
    private var sourceVersion: String?

    func current(
        sourceVersion: String? = nil,
        loader: @Sendable () -> [ClaudeProvider.Credentials]
    ) async -> [ClaudeProvider.Credentials] {
        if isValid, sourceVersion == self.sourceVersion, let cached {
            return cached
        }
        let fresh = loader()
        store(fresh, includesDesktopFallback: false)
        self.sourceVersion = sourceVersion
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
            clear()
            return
        }

        cached = fresh
        self.includesDesktopFallback = includesDesktopFallback

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

    private static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/config.json")
    }

    static func tokenCacheBlob() -> String? {
        guard let data = try? Data(contentsOf: configURL),
              let cfg = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return (cfg["oauth:tokenCacheV2"] as? String) ?? (cfg["oauth:tokenCache"] as? String)
    }

    private static func safeStoragePassword() -> String? {
        Keychain.readGenericPassword(service: safeStorageService)
            .flatMap { String(data: $0, encoding: .utf8) }
    }

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

            var usageWindow: UsageWindow? {
                guard let used = utilization else { return nil }
                return UsageWindow(usedPercent: used, resetsAt: ISO8601Timestamp.date(from: resetsAt))
            }
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
