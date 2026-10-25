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

    func testFallsBackToMonthlyWindowWhenShorterWindowsAreUnavailable() {
        let usage = ProviderUsage(
            fiveHour: nil,
            weekly: nil,
            monthly: UsageWindow(usedPercent: 44, resetsAt: nil))

        XCTAssertEqual(
            MenuBarLabel.tokenText(shortCode: "OC", usage: usage),
            "OC44")
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

    @MainActor func testUnchangedTokensReuseTheRenderedImage() {
        let tokens = [MenuBarLabel.Token(text: "CL38", locked: false)]
        let first = MenuBarLabel.image(tokens: tokens)

        XCTAssertTrue(MenuBarLabel.image(tokens: tokens) === first)

        let changed = MenuBarLabel.image(tokens: [MenuBarLabel.Token(text: "CL", locked: true)])
        XCTAssertFalse(changed === first)
        XCTAssertNotEqual(changed.size, first.size)
    }
}
