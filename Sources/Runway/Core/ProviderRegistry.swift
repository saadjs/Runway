import Foundation

enum ProviderRegistry {
    static let all: [any UsageProvider] = [
        ClaudeProvider(),
        CodexProvider(),
        OpenCodeProvider(),
    ]
}
