import XCTest
@testable import Runway

final class MenuBarLabelTests: XCTestCase {
    func testUsesFiveHourWindowWhenBothWindowsAreAvailable() {
        let usage = ProviderUsage(
            fiveHour: UsageWindow(usedPercent: 23, resetsAt: nil),
            weekly: UsageWindow(usedPercent: 72, resetsAt: nil))

        XCTAssertEqual(
            MenuBarLabel.tokenText(shortCode: "CX", usage: usage),
            "CX23")
    }

    func testFallsBackToWeeklyWindowWhenFiveHourIsUnavailable() {
        let usage = ProviderUsage(
            fiveHour: nil,
            weekly: UsageWindow(usedPercent: 19, resetsAt: nil))

        XCTAssertEqual(
            MenuBarLabel.tokenText(shortCode: "CX", usage: usage),
            "CX19")
    }

    func testShowsDashWhenNoWindowIsAvailable() {
        let usage = ProviderUsage(fiveHour: nil, weekly: nil)

        XCTAssertEqual(
            MenuBarLabel.tokenText(shortCode: "CX", usage: usage),
            "CX–")
    }

    func testHidesPercentageWhenFallbackWeeklyWindowIsExhausted() {
        let usage = ProviderUsage(
            fiveHour: nil,
            weekly: UsageWindow(usedPercent: 100, resetsAt: nil))

        XCTAssertEqual(
            MenuBarLabel.tokenText(shortCode: "CX", usage: usage),
            "CX")
    }
}
