import SwiftUI
import XCTest
@testable import Runway

final class UsageBarTintTests: XCTestCase {
    func testTintMatchesDisplayedRoundedPercent() {
        XCTAssertEqual(UsageBarView.tint(forUsedPercent: 49.4), .green)
        XCTAssertEqual(UsageBarView.tint(forUsedPercent: 49.6), .yellow)
        XCTAssertEqual(UsageBarView.tint(forUsedPercent: 74.6), .orange)
        XCTAssertEqual(UsageBarView.tint(forUsedPercent: 89.6), .red)
        XCTAssertEqual(UsageBarView.tint(forUsedPercent: 100), .red)
    }
}
