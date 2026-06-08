import Foundation

/// A single rate-limit window (e.g. the rolling 5-hour or 7-day window).
struct UsageWindow: Equatable, Sendable {
    /// Percent of the limit consumed, 0...100.
    let usedPercent: Double
    /// When the window resets, if known.
    let resetsAt: Date?

    var clampedFraction: Double { min(max(usedPercent / 100, 0), 1) }
}

/// The two windows Runway surfaces for a provider.
struct ProviderUsage: Equatable, Sendable {
    var fiveHour: UsageWindow?
    var weekly: UsageWindow?
    /// Optional short plan label (e.g. "Plus", "Pro").
    var planLabel: String?

    /// True when the rolling 5-hour window is exhausted: you're blocked until it
    /// resets, even if the weekly window still has headroom.
    var fiveHourReached: Bool { (fiveHour?.usedPercent ?? 0) >= 100 }

    /// True when the weekly window is exhausted: you're blocked until it resets,
    /// so the 5-hour number is moot. The popover still shows both bars.
    var weeklyReached: Bool { (weekly?.usedPercent ?? 0) >= 100 }

    /// Any exhausted window means the provider is currently unusable.
    var isBlocked: Bool { fiveHourReached || weeklyReached }
}

/// Result of a refresh for one provider.
enum ProviderState: Equatable, Sendable {
    case loading
    case loaded(ProviderUsage)
    case failed(String)
}

/// Errors that map to a friendly, actionable message.
enum ProviderError: LocalizedError {
    case notSignedIn(cli: String)
    case tokenExpired(cli: String)
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .notSignedIn(cli):
            return "Not signed in. Run `\(cli)` to log in."
        case let .tokenExpired(cli):
            return "Session expired. Run `\(cli)` to refresh."
        case let .message(text):
            return text
        }
    }
}
