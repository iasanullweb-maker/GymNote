import XCTest
@testable import GymNote

final class TabCoachmarkTests: XCTestCase {
    func testAccountHistorySuppressesCompletedTourOnAnotherDevice() throws {
        var data = AppData.empty
        data.completedCoachmarks = ["workout.plans"]
        let downloaded = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data))
        XCTAssertFalse(CoachmarkHistory.shouldPresent("workout.plans", completed: downloaded.completedCoachmarks, accountReady: true))
        XCTAssertTrue(CoachmarkHistory.shouldPresent("workout.plan.editor", completed: downloaded.completedCoachmarks, accountReady: true))
        XCTAssertTrue(CoachmarkHistory.shouldPresent("workout.plans", completed: AppData.empty.completedCoachmarks, accountReady: true))
    }

    func testGuestAndUnfetchedAccountDoNotShowAutomaticTour() {
        XCTAssertFalse(CoachmarkHistory.shouldPresent("workout.plans", completed: [], accountReady: false))
        XCTAssertTrue(CoachmarkHistory.shouldPresent("workout.plans", completed: [], accountReady: true))
    }

    func testExplicitReplayDoesNotEraseAccountHistory() {
        let completed = ["workout.plans"]
        XCTAssertTrue(CoachmarkHistory.shouldPresent("workout.plans", completed: completed, accountReady: false, replayCompleted: []))
        XCTAssertFalse(CoachmarkHistory.shouldPresent("workout.plans", completed: completed, accountReady: true, replayCompleted: ["workout.plans"]))
        XCTAssertFalse(CoachmarkHistory.shouldPresent("workout.plans", completed: completed, accountReady: true))
    }

    func testDetailToursHaveIndependentIDs() {
        let tours: [TabCoachTour] = [.planEditor, .exercisePicker, .exerciseSettings(cindy: false),
                                    .exerciseSettings(cindy: true), .planCopy, .starter, .dailyEditor]
        XCTAssertEqual(Set(tours.map(\.id)).count, 7)
        for tour in tours {
            XCTAssertFalse(tour.steps.isEmpty)
            XCTAssertFalse(CoachmarkHistory.shouldPresent(tour.id, completed: [tour.id], accountReady: true))
        }
    }

    @MainActor
    func testStoreHistorySurvivesCloudReplacementAndAccountSwitch() async throws {
        let previous = SharedStore.testingDirectory
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        SharedStore.testingDirectory = folder
        defer {
            SharedStore.testingDirectory = previous
            try? FileManager.default.removeItem(at: folder)
        }
        let firstID = UUID(), secondID = UUID()
        let first = try SharedStore.activate(userID: firstID)
        let before = try SharedStore.snapshot(userID: firstID)
        var edited = before.data
        edited.completedCoachmarks = ["workout.plan.editor"]
        _ = try SharedStore.persistEdits(from: before.data, to: edited, selection: first)
        let saved = try SharedStore.snapshot(userID: firstID)
        // Older app uploads omit this field. Adopting its cloud payload keeps our completion.
        try SharedStore.replaceWithCloud(.empty, version: 2, revision: saved.revision, selection: first)
        XCTAssertEqual(try SharedStore.snapshot(userID: firstID).data.completedCoachmarks, ["workout.plan.editor"])
        let second = try SharedStore.activate(userID: secondID)
        XCTAssertTrue(try SharedStore.snapshot(userID: secondID).data.completedCoachmarks.isEmpty)
        XCTAssertThrowsError(try SharedStore.persistEdits(from: before.data, to: edited, selection: first))
        _ = try SharedStore.activate(userID: firstID)
        XCTAssertEqual(try SharedStore.snapshot(userID: firstID).data.completedCoachmarks, ["workout.plan.editor"])
        XCTAssertNotEqual(first.generation, second.generation)
    }

    @MainActor
    func testRepeatedReplayRestartsSessionAndAccountSwitchClearsReplay() async throws {
        let previous = SharedStore.testingDirectory
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        SharedStore.testingDirectory = folder
        defer {
            SharedStore.testingDirectory = previous
            try? FileManager.default.removeItem(at: folder)
        }
        let model = AppModel()
        model.account = AccountModel(model: model, client: nil, initialConnection: .offline, monitorConnectivity: false)
        model.replayCoachmarks()
        let generation = model.coachmarkReplayGeneration
        model.replayCompletedCoachmarks.insert("settings")
        model.replayCoachmarks()
        XCTAssertNotEqual(model.coachmarkReplayGeneration, generation)
        XCTAssertTrue(model.replayCompletedCoachmarks.isEmpty)
        try await model.switchAccount(UUID())
        XCTAssertFalse(model.replayingCoachmarks)
        XCTAssertTrue(model.replayCompletedCoachmarks.isEmpty)
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
