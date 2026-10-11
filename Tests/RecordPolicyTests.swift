import XCTest
@testable import GymNote

final class RecordPolicyTests: XCTestCase {
    private let move = Exercise(name: "푸쉬업", sets: 2, detail: "10회")
    private let day = Calendar.current.startOfDay(for: Date()).addingTimeInterval(3600)
    private var key: String { AppData.exerciseKey(move.name) }

    private func journal(_ reps: Int, on date: Date) -> WorkoutSession {
        var session = WorkoutSession(startedAt: date, plan: DayPlan(title: "운동", exercises: [move]))
        session.completedSets[move.id.uuidString] = 1
        session.actualReps[move.id.uuidString] = [reps]
        session.endedAt = date.addingTimeInterval(60)
        return session
    }

    private func started() -> AppData {
        var data = AppData.empty
        data.workouts = [journal(20, on: day.addingTimeInterval(-86400))]
        data.preserveExistingBestRecords()
        data.scheduledPlans[DayKey.key(day)] = DayPlan(title: "운동", exercises: [move])
        XCTAssertTrue(data.startWorkout(at: day))
        return data
    }

    func testPastJournalEditsAdditionsAndDeletionsPreserveBest() {
        var data = started()
        let id = data.workouts[0].id
        data.updateRepetitions(sessionID: id, exerciseID: move.id, set: 0, value: 99)
        data.workouts.append(journal(100, on: day.addingTimeInterval(-172800)))
        data.workouts.removeAll { $0.id == id }
        XCTAssertEqual(data.exerciseRecords()[key]?.bestSet?.value, 20)
    }

    func testTodaysExecutionUpdatesBestAndUsesPlannedRepetitions() {
        var data = started()
        data.changeSets(move.id, by: 1, on: day, at: day)
        data.changeSets(move.id, by: 1, on: day, actualReps: 25, at: day)
        XCTAssertNil(data.activeWorkout)
        XCTAssertEqual(data.workouts.last?.actualReps[move.id.uuidString], [10, 25])
        XCTAssertEqual(data.exerciseRecords()[key]?.bestSet?.value, 25)
        XCTAssertEqual(data.exerciseRecords()[key]?.bestDay?.value, 35)
    }

    func testOldSessionCompletedTodayDoesNotUpdateBest() {
        var data = started()
        data.changeSets(move.id, by: 1, on: day, actualReps: 99, at: day.addingTimeInterval(86400))
        data.finishWorkout(at: day.addingTimeInterval(86400))
        XCTAssertEqual(data.exerciseRecords()[key]?.bestSet?.value, 20)
        XCTAssertEqual(data.workouts.last?.actualReps[move.id.uuidString], [99])
    }

    func testWidgetOnlyCompletionSavesJournalWithoutUpdatingBest() {
        var data = started()
        data.completeSetFromWidget(move.id, now: day)
        data.completeSetFromWidget(move.id, now: day)
        XCTAssertEqual(data.workouts.count, 2)
        XCTAssertEqual(data.recordWorkouts?.count, 1)
        XCTAssertEqual(data.exerciseRecords()[key]?.bestDay?.value, 20)
    }

    func testMixedWidgetAndExecutionOnlyCreditsExecutionSet() {
        var data = started()
        data.completeSetFromWidget(move.id, now: day)
        data.changeSets(move.id, by: 1, on: day, actualReps: 25, at: day)
        XCTAssertEqual(data.workouts.last?.actualReps[move.id.uuidString], [10, 25])
        XCTAssertEqual(data.exerciseRecords()[key]?.bestDay?.value, 25)
    }

    func testUndoRemovesEligibilityBeforeRecompletion() {
        var data = started()
        data.changeSets(move.id, by: 1, on: day, actualReps: 99, at: day)
        data.changeSets(move.id, by: -1, on: day, at: day)
        data.completeSetFromWidget(move.id, now: day)
        data.finishWorkout(at: day)
        XCTAssertEqual(data.exerciseRecords()[key]?.bestSet?.value, 20)
    }

    func testConcurrentWidgetAndExecutionRetainBothCountsAndOnlyAppAchievement() {
        let base = started()
        var widget = base, app = base
        widget.completeSetFromWidget(move.id, now: day)
        app.changeSets(move.id, by: 1, on: day, actualReps: 25, at: day)
        let merged = widget.applyingEdits(from: base, to: app)
        XCTAssertNil(merged.activeWorkout)
        XCTAssertEqual(merged.workouts.last?.actualReps[move.id.uuidString], [10, 25])
        XCTAssertEqual(merged.exerciseRecords()[key]?.bestDay?.value, 25)
    }

    func testLegacyDecodeAndPolicyRoundTripKeepOriginalBest() throws {
        var original = AppData.empty
        original.workouts = [journal(20, on: day)]
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        fields.removeValue(forKey: "recordWorkouts")
        var decoded = try JSONDecoder().decode(AppData.self, from: JSONSerialization.data(withJSONObject: fields))
        XCTAssertNil(decoded.recordWorkouts)
        decoded.preserveExistingBestRecords()
        decoded.workouts.removeAll()
        let restored = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(restored, decoded)
        XCTAssertEqual(restored.exerciseRecords()[key]?.bestSet?.value, 20)
    }

    func testGuestImportPreservesDeletedJournalAchievementAndIsIdempotent() {
        var guest = started()
        guest.activeWorkout = nil
        guest.workouts.removeAll()
        let imported = AppData.empty.importingGuest(guest)
        XCTAssertEqual(imported.exerciseRecords()[key]?.bestSet?.value, 20)
        XCTAssertEqual(imported.importingGuest(guest), imported)
    }

    func testCompatibleLegacyManualBestIsProjectedWithoutChangingStoredIDs() {
        var data = AppData.empty
        let old = data.recordTypes[0]
        let entry = RecordEntry(typeID: old.id, date: day, value: 30)
        data.records = [entry]
        let current = CatalogRecordType.defaults[0]
        XCTAssertEqual(data.recordProjection(catalog: [current]).best(current.recordType)?.value, 30)
        XCTAssertEqual(data.records[0].typeID, old.id)
        var incompatible = current
        incompatible.unit = "kg"
        XCTAssertNil(data.recordProjection(catalog: [incompatible]).best(incompatible.recordType))
    }

    func testAdministratorCatalogHasNoThreeExerciseLimitAndRejectsPrivateExercises() {
        var catalog = CatalogRecordType.defaults
        var extra = catalog[0]
        extra.id = "extra"; extra.name = "스쿼트"; extra.position = 3
        catalog.append(extra)
        XCTAssertEqual(AppData.empty.recordDisplayTypes(catalog: catalog).filter { $0.id.hasPrefix("common-") || $0.id == "extra" }.count, 4)
        XCTAssertTrue(AppData.empty.isRegisteredExercise(extra.makeExercise(), catalog: catalog))
        XCTAssertFalse(AppData.empty.isRegisteredExercise(Exercise(name: "개인 운동", sets: 1, detail: "10회"), catalog: catalog))
        extra.active = false
        XCTAssertFalse(AppData.empty.isRegisteredExercise(extra.makeExercise(), catalog: [extra]))
    }
}
