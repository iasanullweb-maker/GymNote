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
}
