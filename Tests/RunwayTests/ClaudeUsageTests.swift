import Foundation
import XCTest
@testable import Runway

final class ClaudeUsageTests: XCTestCase {
    func testFableScopedWeeklyLimitIsShownSeparately() throws {
        let usage = try decode("""
        {
          "five_hour": { "utilization": 19.0, "resets_at": "2026-11-24T02:50:00.108343+00:00" },
          "seven_day": { "utilization": 63.0, "resets_at": "2026-11-24T05:00:00.108363+00:00" },
          "limits": [
            { "kind": "session", "group": "session", "percent": 19, "resets_at": "2026-11-24T02:50:00.108343+00:00", "scope": null },
            { "kind": "weekly_all", "group": "weekly", "percent": 63, "resets_at": "2026-11-24T05:00:00.108363+00:00", "scope": null },
            { "kind": "weekly_scoped", "group": "weekly", "percent": 89, "resets_at": "2026-11-24T05:00:00.108591+00:00",
              "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null } }
          ]
        }
        """).providerUsage(planLabel: "Max")

        XCTAssertEqual(usage.fiveHour?.usedPercent, 19)
        XCTAssertEqual(usage.weekly?.usedPercent, 63)
        XCTAssertEqual(usage.modelWeekly.map(\.title), ["Fable weekly"])
        XCTAssertEqual(usage.modelWeekly.first?.window.usedPercent, 89)
        XCTAssertEqual(
            usage.modelWeekly.first?.window.resetsAt,
            ISO8601Timestamp.date(from: "2026-11-24T05:00:00.108591+00:00"))
    }

    func testPlanWithoutFableLimitShowsNoExtraBar() throws {
        let usage = try decode("""
        {
          "five_hour": { "utilization": 5.0, "resets_at": null },
          "seven_day": { "utilization": 10.0, "resets_at": null },
          "limits": [ { "kind": "weekly_all", "percent": 10, "scope": null } ]
        }
        """).providerUsage(planLabel: "Pro")

        XCTAssertTrue(usage.modelWeekly.isEmpty)
        XCTAssertEqual(usage.weekly?.usedPercent, 10)
    }

    func testFableLimitReachedDoesNotBlockClaude() throws {
        let usage = try decode("""
        {
          "five_hour": { "utilization": 5.0 },
          "seven_day": { "utilization": 50.0 },
          "limits": [ { "kind": "weekly_scoped", "percent": 100, "scope": { "model": { "display_name": "Fable" } } } ]
        }
        """).providerUsage(planLabel: nil)

        XCTAssertEqual(usage.modelWeekly.first?.window.usedPercent, 100)
        XCTAssertFalse(usage.isBlocked)
    }

    func testMalformedLimitsKeepsMainWindows() throws {
        let usage = try decode("""
        { "five_hour": { "utilization": 7.0 }, "seven_day": { "utilization": 8.0 }, "limits": { "unexpected": true } }
        """).providerUsage(planLabel: nil)

        XCTAssertEqual(usage.fiveHour?.usedPercent, 7)
        XCTAssertEqual(usage.weekly?.usedPercent, 8)
        XCTAssertTrue(usage.modelWeekly.isEmpty)
    }

    func testOneMalformedLimitDoesNotHideFableBar() throws {
        let usage = try decode("""
        {
          "five_hour": { "utilization": 1.0 },
          "seven_day": { "utilization": 2.0 },
          "limits": [
            { "kind": "session", "percent": "19%" },
            { "kind": "weekly_scoped", "percent": 89, "scope": { "model": { "display_name": "Fable" } } }
          ]
        }
        """).providerUsage(planLabel: nil)

        XCTAssertEqual(usage.modelWeekly.map(\.title), ["Fable weekly"])
    }

    private func decode(_ json: String) throws -> ClaudeUsageAPI.Response {
        try JSONDecoder().decode(ClaudeUsageAPI.Response.self, from: Data(json.utf8))
    }
}
