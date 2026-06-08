import Foundation

/// A monitored usage source. Add a new provider by conforming a type here and
/// registering it in `ProviderRegistry`.
protocol UsageProvider: Sendable {
    /// Stable identifier (used as a dictionary key and for ordering).
    var id: String { get }
    /// Human-readable name shown in the menu.
    var displayName: String { get }
    /// Short code shown in the menu-bar label (e.g. "CL", "CX").
    var shortCode: String { get }
    /// Base name of the bundled vector logo (e.g. "claude" -> claude.pdf),
    /// rendered as a template image so it adapts to light/dark.
    var logoResource: String { get }

    /// Fetch current usage. Throws `ProviderError` (or any `Error`) on failure.
    func fetchUsage() async throws -> ProviderUsage
}
