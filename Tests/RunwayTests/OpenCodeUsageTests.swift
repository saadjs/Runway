import Foundation
import XCTest
@testable import Runway

final class OpenCodeUsageTests: XCTestCase {
    func testMapsAllThreeWindows() throws {
        let usage = try decode("""
        {
          "usage": {
            "rolling": { "status": "ok", "percent": 12, "resetsAt": "2026-08-16T07:25:27.719Z" },
            "weekly": { "status": "ok", "percent": 37, "resetsAt": "2026-08-17T00:00:00.719Z" },
            "monthly": { "status": "ok", "percent": 18, "resetsAt": "2026-09-15T03:32:52.719Z" }
          }
        }
        """).providerUsage

        XCTAssertEqual(usage.fiveHour?.usedPercent, 12)
        XCTAssertEqual(usage.weekly?.usedPercent, 37)
        XCTAssertEqual(usage.monthly?.usedPercent, 18)
        XCTAssertEqual(usage.planLabel, "Go")

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(usage.fiveHour?.resetsAt, formatter.date(from: "2026-08-16T07:25:27.719Z"))
    }

    /// Reset timestamps without fractional seconds still parse.
    func testParsesResetWithoutFractionalSeconds() throws {
        let usage = try decode("""
        { "usage": { "rolling": { "percent": 5, "resetsAt": "2026-08-16T07:25:27Z" } } }
        """).providerUsage

        let formatter = ISO8601DateFormatter()
        XCTAssertEqual(usage.fiveHour?.resetsAt, formatter.date(from: "2026-08-16T07:25:27Z"))
        XCTAssertNil(usage.weekly)
    }

    func testMissingWindowsDoNotFakeZeroUsage() throws {
        let usage = try decode(#"{ "usage": {} }"#).providerUsage

        XCTAssertNil(usage.fiveHour)
        XCTAssertNil(usage.weekly)
        XCTAssertNil(usage.monthly)
        XCTAssertFalse(usage.isBlocked)
    }

    /// The monthly cap is the longest lockout, and the one most easily hit:
    /// an exhausted month must read as blocked even with 5-hour/weekly headroom.
    func testExhaustedMonthlyCapReadsAsBlocked() throws {
        let usage = try decode("""
        {
          "usage": {
            "rolling": { "percent": 0 },
            "weekly": { "percent": 12 },
            "monthly": { "percent": 100 }
          }
        }
        """).providerUsage

        XCTAssertTrue(usage.monthlyReached)
        XCTAssertTrue(usage.isBlocked)
        XCTAssertEqual(MenuBarLabel.tokenText(shortCode: "OC", usage: usage), "OC")
    }

    func testExhaustedFiveHourWindowReadsAsBlocked() throws {
        let usage = try decode("""
        { "usage": { "rolling": { "percent": 100 }, "weekly": { "percent": 61 } } }
        """).providerUsage

        XCTAssertTrue(usage.isBlocked)
        XCTAssertEqual(
            MenuBarLabel.tokenText(shortCode: "OC", usage: usage), "OC")
    }

    // MARK: - auth.json

    func testReadsAPIKeyFromCLIAuthFile() throws {
        let key = OpenCodeAuth.apiKey(fromAuthJSON: Data("""
        {
          "openai": { "type": "oauth", "access": "ey…", "refresh": "rt…" },
          "opencode-go": { "type": "api", "key": "sk-test-key" }
        }
        """.utf8))

        XCTAssertEqual(key, "sk-test-key")
    }

    func testMissingOrEmptyGoEntryYieldsNoKey() throws {
        XCTAssertNil(OpenCodeAuth.apiKey(fromAuthJSON: Data(#"{"openai":{"type":"oauth"}}"#.utf8)))
        XCTAssertNil(OpenCodeAuth.apiKey(fromAuthJSON: Data(#"{"opencode-go":{"type":"api","key":""}}"#.utf8)))
        XCTAssertNil(OpenCodeAuth.apiKey(fromAuthJSON: Data("not json".utf8)))
    }

    /// A window the API flags as not-ok is dropped, not drawn as 0% used.
    func testNonOKWindowIsDroppedRatherThanShownEmpty() throws {
        let usage = try decode("""
        {
          "usage": {
            "rolling": { "status": "unavailable", "percent": 0 },
            "weekly": { "status": "OK", "percent": 40 }
          }
        }
        """).providerUsage

        XCTAssertNil(usage.fiveHour)
        XCTAssertEqual(usage.weekly?.usedPercent, 40)
    }

    func testKeyIsTrimmedSoTheAuthHeaderStaysWellFormed() throws {
        XCTAssertEqual(
            OpenCodeAuth.apiKey(fromAuthJSON: Data(#"{"opencode-go":{"key":"  sk-test-key\n"}}"#.utf8)),
            "sk-test-key")
        XCTAssertNil(OpenCodeAuth.apiKey(fromAuthJSON: Data(#"{"opencode-go":{"key":"   "}}"#.utf8)))
    }

    func testAuthURLHonoursDataHomeOverride() throws {
        XCTAssertEqual(
            OpenCodeAuth.authURL(dataHome: "/tmp/xdg").path, "/tmp/xdg/opencode/auth.json")
        XCTAssertEqual(
            OpenCodeAuth.authURL(dataHome: "  ").path,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/share/opencode/auth.json").path)
    }

    /// The packaged app doesn't inherit the shell profile, so the login shell is
    /// the fallback for vars the CLI relies on.
    func testLoginShellEnvRecoversAProfileVariable() throws {
        LoginShellEnv.resetCacheForTesting()
        XCTAssertNil(LoginShellEnv.value("RUNWAY_DEFINITELY_UNSET_VAR"))
        XCTAssertEqual(LoginShellEnv.value("HOME")?.isEmpty, false)
        XCTAssertNil(LoginShellEnv.value("BAD; rm -rf /"))
    }

    private func decode(_ json: String) throws -> OpenCodeUsageAPI.Response {
        try JSONDecoder().decode(OpenCodeUsageAPI.Response.self, from: Data(json.utf8))
    }
}
