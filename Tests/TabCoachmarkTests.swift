import XCTest
@testable import GymNote

final class TabCoachmarkTests: XCTestCase {
    func testCompletingWorkoutPlanDoesNotSuppressOtherFirstVisits() {
        let saved = CoachmarkHistory.completing("workout.plans", in: "")
        XCTAssertTrue(CoachmarkHistory.contains("workout.plans", in: saved))
        for id in ["daily.plans", "workout.today", "workout.records", "friends", "settings", "workout.plan"] {
            XCTAssertFalse(CoachmarkHistory.contains(id, in: saved), id)
        }
    }

    func testCompletionSurvivesReloadWithoutDuplicatingOrLosingOtherTabs() throws {
        let name = "gymnote.coachmarks.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var saved = CoachmarkHistory.completing("workout.plans", in: "")
        saved = CoachmarkHistory.completing("daily.plans", in: saved)
        saved = CoachmarkHistory.completing("workout.plans", in: saved)
        defaults.set(saved, forKey: CoachmarkHistory.key)
        let reloaded = try XCTUnwrap(UserDefaults(suiteName: name)?.string(forKey: CoachmarkHistory.key))
        XCTAssertEqual(reloaded.split(separator: "\n").count, 2)
        XCTAssertTrue(CoachmarkHistory.contains("workout.plans", in: reloaded))
        XCTAssertTrue(CoachmarkHistory.contains("daily.plans", in: reloaded))
        XCTAssertFalse(CoachmarkHistory.contains("settings", in: reloaded))
    }

    func testWorkspaceSpecificToursAndSharedTabsHaveStableIndependentIDs() {
        var ids = Set<String>()
        for tab in 0...4 {
            let workout = TabCoachTour.tour(tab: tab, daily: false)
            let daily = TabCoachTour.tour(tab: tab, daily: true)
            XCTAssertFalse(workout.steps.isEmpty)
            XCTAssertFalse(daily.steps.isEmpty)
            if tab < 3 { XCTAssertNotEqual(workout.id, daily.id) }
            else { XCTAssertEqual(workout.id, daily.id) }
            ids.insert(workout.id)
            ids.insert(daily.id)
        }
        XCTAssertEqual(ids.count, 8)
    }
    func testExplanationStaysBesideVisibleControlOnPhoneAndPad() {
        for size in [CGSize(width: 393, height: 852), CGSize(width: 834, height: 1194)] {
            for y in [CGFloat(60), size.height - 140] {
                let target = CGRect(x: size.width - 60, y: y, width: 44, height: 44)
                let placement = CoachmarkPlacement(target: target, size: size, cardHeight: 210)
                XCTAssertTrue(placement.showsHighlight)
                XCTAssertFalse(placement.card.intersects(placement.highlight))
                XCTAssertGreaterThanOrEqual(placement.card.minX, 16)
                XCTAssertLessThanOrEqual(placement.card.maxX, size.width - 16)
                XCTAssertGreaterThanOrEqual(placement.card.minY, 8)
                XCTAssertLessThanOrEqual(placement.card.maxY, size.height - 8)
                XCTAssertEqual(placement.below, y < size.height / 2)
            }
        }
    }

    func testMissingOrOffscreenControlNeverHighlightsWholeScreen() {
        let size = CGSize(width: 393, height: 852)
        for target in [nil, CGRect(x: 20, y: 950, width: 100, height: 44)] as [CGRect?] {
            XCTAssertFalse(CoachmarkPlacement(target: target, size: size, cardHeight: 210).showsHighlight)
        }
    }

    func testLargeExplanationKeepsControlCoveredWhenThereIsNoRoom() {
        let placement = CoachmarkPlacement(target: CGRect(x: 100, y: 130, width: 100, height: 44),
                                          size: CGSize(width: 700, height: 320), cardHeight: 240)
        XCTAssertFalse(placement.showsHighlight)
        XCTAssertGreaterThanOrEqual(placement.card.minY, 8)
        XCTAssertLessThanOrEqual(placement.card.maxY, 312)
    }

}
