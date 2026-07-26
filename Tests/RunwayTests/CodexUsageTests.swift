import Foundation
import XCTest
@testable import Runway

final class CodexUsageTests: XCTestCase {
    func testWeeklyWindowPromotedToPrimaryWhenFiveHourLimitIsDisabled() throws {
        let response = try decode("""
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window": {
              "used_percent": 17,
              "limit_window_seconds": 604800,
              "reset_at": 1785635172
            },
            "secondary_window": null
          }
        }
        """)

        XCTAssertNil(response.providerUsage.fiveHour)
        XCTAssertEqual(
            response.providerUsage.weekly,
            UsageWindow(
                usedPercent: 17,
                resetsAt: Date(timeIntervalSince1970: 1785635172)))
        XCTAssertEqual(response.providerUsage.planLabel, "Plus")
    }

    func testNormalResponseClassifiesBothWindowsByDuration() throws {
        let response = try decode("""
        {
          "rate_limit": {
            "primary_window": {
              "used_percent": 23,
              "limit_window_seconds": 18000,
              "reset_at": 1785086340
            },
            "secondary_window": {
              "used_percent": 22,
              "limit_window_seconds": 604800,
              "reset_at": 1785297540
            }
          }
        }
        """)

        XCTAssertEqual(response.providerUsage.fiveHour?.usedPercent, 23)
        XCTAssertEqual(response.providerUsage.weekly?.usedPercent, 22)
    }

    func testOlderResponseWithoutDurationsUsesPositionalFallback() throws {
        let response = try decode("""
        {
          "rate_limit": {
            "primary_window": {
              "used_percent": 31,
              "reset_at": 1785086340
            },
            "secondary_window": {
              "used_percent": 42,
              "reset_at": 1785297540
            }
          }
        }
        """)

        XCTAssertEqual(response.providerUsage.fiveHour?.usedPercent, 31)
        XCTAssertEqual(response.providerUsage.weekly?.usedPercent, 42)
    }

    private func decode(_ json: String) throws -> CodexUsageAPI.Response {
        try JSONDecoder().decode(
            CodexUsageAPI.Response.self,
            from: Data(json.utf8))
    }
}
