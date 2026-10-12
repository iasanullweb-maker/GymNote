import Foundation
import XCTest
@testable import GymNote

final class RestIntentTests: XCTestCase {
    func testSpokenDurationConvertsMinutesAndSeconds() {
        XCTAssertEqual(StartSpokenRestIntent.seconds(for: .init(value: 1.5, unit: .minutes)), 90)
        XCTAssertEqual(StartSpokenRestIntent.seconds(for: .init(value: 45, unit: .seconds)), 45)
        XCTAssertEqual(StartSpokenRestIntent.seconds(for: .init(value: 2.25, unit: .minutes)), 135)
    }

    func testFractionalSecondsNeverShortenRest() {
        XCTAssertEqual(StartSpokenRestIntent.seconds(for: .init(value: 90.1, unit: .seconds)), 91)
        XCTAssertEqual(StartSpokenRestIntent.seconds(for: .init(value: 5, unit: .seconds)), 5)
    }

    func testInvalidDurationDoesNotBecomeATimer() {
        for value in [0.0, -30, 4.9, Double.nan, Double.infinity, Double(Int.max)] {
            XCTAssertNil(StartSpokenRestIntent.seconds(for: .init(value: value, unit: .seconds)))
        }
    }

    func testExistingWidgetIntentKeepsExplicitTimeAndAccount() {
        let intent = StartRestIntent(seconds: 120, generation: "widget-account")
        XCTAssertEqual(intent.seconds, 120)
        XCTAssertEqual(intent.generation, "widget-account")
    }
}
