import Foundation
import XCTest
@testable import Runway

final class ClaudeCredentialCacheTests: XCTestCase {
    func testCredentialRejectionAllowsFallback() {
        XCTAssertTrue(ClaudeProvider.allowsCredentialFallback(
            after: ProviderError.tokenExpired(cli: "claude")))
    }

    func testTransientFailureDoesNotAllowFallback() {
        XCTAssertFalse(ClaudeProvider.allowsCredentialFallback(
            after: ProviderError.message("Rate limited by Anthropic.")))
        XCTAssertFalse(ClaudeProvider.allowsCredentialFallback(
            after: URLError(.notConnectedToInternet)))
    }

    func testEmptyLookupIsNotCached() async {
        let cache = CredentialCache()
        let loads = LockedCounter()

        let empty = await cache.current {
            loads.increment()
            return []
        }
        XCTAssertTrue(empty.isEmpty)

        let signedIn = credential(token: "new-token")
        let refreshed = await cache.current {
            loads.increment()
            return [signedIn]
        }

        XCTAssertEqual(refreshed.map(\.accessToken), ["new-token"])
        XCTAssertEqual(loads.value, 2)
    }

    func testExpiredOnlyLookupIsNotCached() async {
        let cache = CredentialCache()
        let loads = LockedCounter()
        let expired = credential(
            token: "expired-token",
            expiresAt: Date().addingTimeInterval(-60))

        _ = await cache.current {
            loads.increment()
            return [expired]
        }
        let rotated = credential(token: "rotated-token")
        let refreshed = await cache.current {
            loads.increment()
            return [rotated]
        }

        XCTAssertEqual(refreshed.map(\.accessToken), ["rotated-token"])
        XCTAssertEqual(loads.value, 2)
    }

    func testExpiredCredentialDoesNotInvalidateUsableFallbackCache() async {
        let cache = CredentialCache()
        let primaryLoads = LockedCounter()
        let desktopLoads = LockedCounter()
        let expired = credential(
            token: "stale-cli",
            expiresAt: Date().addingTimeInterval(-60))
        let rejectedButUnexpired = credential(
            token: "rejected-cli",
            expiresAt: Date().addingTimeInterval(10 * 60))
        let desktop = credential(
            token: "desktop-token",
            expiresAt: Date().addingTimeInterval(20 * 60))

        _ = await cache.current {
            primaryLoads.increment()
            return [expired, rejectedButUnexpired]
        }
        let combined = await cache.includingDesktopFallback(
            primaryCandidates: [expired, rejectedButUnexpired]
        ) {
            desktopLoads.increment()
            return [desktop]
        }
        let cached = await cache.current {
            primaryLoads.increment()
            return []
        }

        XCTAssertEqual(
            combined.map(\.accessToken),
            ["stale-cli", "rejected-cli", "desktop-token"])
        XCTAssertEqual(
            cached.map(\.accessToken),
            ["stale-cli", "rejected-cli", "desktop-token"])
        XCTAssertEqual(primaryLoads.value, 1)
        XCTAssertEqual(desktopLoads.value, 1)
    }

    func testEmptyDesktopFallbackIsRetried() async {
        let cache = CredentialCache()
        let desktopLoads = LockedCounter()
        let rejectedCLI = credential(token: "rejected-cli")

        _ = await cache.current { [rejectedCLI] }
        let first = await cache.includingDesktopFallback(
            primaryCandidates: [rejectedCLI]
        ) {
            desktopLoads.increment()
            return []
        }
        let desktop = credential(token: "desktop-token")
        let second = await cache.includingDesktopFallback(
            primaryCandidates: [rejectedCLI]
        ) {
            desktopLoads.increment()
            return [desktop]
        }

        XCTAssertEqual(first.map(\.accessToken), ["rejected-cli"])
        XCTAssertEqual(
            second.map(\.accessToken),
            ["rejected-cli", "desktop-token"])
        XCTAssertEqual(desktopLoads.value, 2)
    }

    private func credential(
        token: String,
        expiresAt: Date? = nil
    ) -> ClaudeProvider.Credentials {
        ClaudeProvider.Credentials(
            accessToken: token,
            expiresAt: expiresAt,
            planLabel: nil)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
