import Foundation

/// The single place that declares which providers Runway shows.
/// Append a new `UsageProvider` here to support another app.
enum ProviderRegistry {
    static let all: [any UsageProvider] = [
        ClaudeProvider(),
        CodexProvider(),
    ]
}
