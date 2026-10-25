import Foundation

struct UsageWindow: Equatable, Sendable {
    let usedPercent: Double
    let resetsAt: Date?

    var clampedFraction: Double { min(max(usedPercent / 100, 0), 1) }
}

struct ProviderUsage: Equatable, Sendable {
    var fiveHour: UsageWindow?
    var weekly: UsageWindow?
    var monthly: UsageWindow?
    var planLabel: String?

    var fiveHourReached: Bool { (fiveHour?.usedPercent ?? 0) >= 100 }

    var weeklyReached: Bool { (weekly?.usedPercent ?? 0) >= 100 }

    var monthlyReached: Bool { (monthly?.usedPercent ?? 0) >= 100 }

    var isBlocked: Bool { fiveHourReached || weeklyReached || monthlyReached }
}

enum ISO8601Timestamp {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let whole = ISO8601DateFormatter()

    static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        return fractional.date(from: string) ?? whole.date(from: string)
    }
}

enum ProviderState: Equatable, Sendable {
    case loading
    case loaded(ProviderUsage)
    case failed(String)
}

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
