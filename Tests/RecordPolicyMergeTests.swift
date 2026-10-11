import XCTest
@testable import GymNote

final class RecordPolicyMergeTests: XCTestCase {
    private let day = Calendar.current.startOfDay(for: Date()).addingTimeInterval(3600)
    private let move = Exercise(name: "푸쉬업", sets: 3, detail: "10회")
    private var key: String { AppData.exerciseKey(move.name) }

    private func journal(_ values: [Int], on date: Date) -> WorkoutSession {
        var exercise = move
        exercise.sets = max(values.count, 1)
        var session = WorkoutSession(startedAt: date, plan: DayPlan(title: "기록", exercises: [exercise]))
        session.completedSets[exercise.id.uuidString] = values.count
        session.actualReps[exercise.id.uuidString] = values.map { Optional($0) }
        session.endedAt = date.addingTimeInterval(60)
        return session
    }

    private func started() -> AppData {
        var data = AppData.empty
        data.workouts = [journal([20], on: day.addingTimeInterval(-86400))]
        data.preserveExistingBestRecords()
        data.scheduledPlans[DayKey.key(day)] = DayPlan(title: "운동", exercises: [move])
        XCTAssertTrue(data.startWorkout(at: day))
        return data
    }

    func testLegacyCloudJournalEditDoesNotReplacePreservedAchievement() throws {
        var base = AppData.empty
        base.workouts = [journal([20], on: day.addingTimeInterval(-86400))]
        base.preserveExistingBestRecords()
        var remote = base
        remote.recordWorkouts = nil
        remote.workouts[0].actualReps[move.id.uuidString] = [100]
        var local = base
        local.defaultRest = base.defaultRest + 10
        let merged = try XCTUnwrap(remote.mergingCloud(local: local, base: base))
        XCTAssertEqual(merged.workouts[0].repetitions(move, set: 0), 100)
        XCTAssertEqual(merged.defaultRest, local.defaultRest)
        XCTAssertEqual(merged.exerciseRecords()[key]?.bestSet?.value, 20)
    }

    func testLegacyFinishedSessionKeepsMigratedBaselineDuringUnrelatedEdit() {
        var base = AppData.empty
        let session = journal([20], on: day)
        var active = session
        active.endedAt = nil
        base.activeWorkout = active
        base.logs = [DayLog(day: DayKey.key(day), doneSets: [move.id.uuidString: 1])]
        var latest = base
        latest.activeWorkout = nil
        latest.workouts = [session]
        var edited = base
        edited.defaultRest = base.defaultRest + 10
        let merged = latest.applyingEdits(from: base, to: edited)
        XCTAssertNil(merged.activeWorkout)
        XCTAssertEqual(merged.exerciseRecords()[key]?.bestSet?.value, 20)
        XCTAssertEqual(merged.exerciseRecords()[key]?.bestDay?.value, 20)
    }

    func testUndoThenWidgetRecompletionAtSameCountDoesNotRestoreEligibility() {
        var base = started()
        base.changeSets(move.id, by: 1, on: day, actualReps: 99, at: day)
        var edited = base
        edited.changeSets(move.id, by: -1, on: day, at: day)
        edited.completeSetFromWidget(move.id, now: day)
        var merged = base.applyingEdits(from: base, to: edited)
        XCTAssertEqual(merged.activeWorkout?.done, 1)
        merged.finishWorkout(at: day)
        XCTAssertEqual(merged.exerciseRecords()[key]?.bestSet?.value, 20)
    }

    func testWidgetWrapAndSameCountLocalEligibilityChangeDoNotIndexEmptyArrays() {
        var base = started()
        var shortMove = move
        shortMove.sets = 1
        let other = Exercise(name: "풀업", sets: 1, detail: "10회")
        base.activeWorkout?.plan.exercises = [shortMove, other]
        let entry = RecordEntry(typeID: "pushup", date: day, value: 99)
        base.changeSets(shortMove.id, by: 1, on: day, actualReps: 99, at: day, recordEntry: entry)
        var widget = base
        widget.completeSetFromWidget(shortMove.id, now: day)
        XCTAssertEqual(widget.activeWorkout?.doneSets(shortMove), 0)
        var edited = base
        edited.changeSets(shortMove.id, by: -1, on: day, at: day)
        edited.completeSetFromWidget(shortMove.id, now: day)
        var merged = widget.applyingEdits(from: base, to: edited)
        XCTAssertEqual(merged.activeWorkout?.doneSets(shortMove), 0)
        merged.finishWorkout(at: day)
        XCTAssertEqual(merged.exerciseRecords()[key]?.bestSet?.value, 20)
        XCTAssertFalse(merged.records.contains { $0.id == entry.id })
    }

    func testCompactionRetainsMaximumAndSameDayTotalsAcrossRepeatedCompaction() {
        var data = AppData.empty
        data.workouts = [journal([10, 20], on: day),
                         journal([25], on: day.addingTimeInterval(120)),
                         journal([30], on: day.addingTimeInterval(86400))]
        data.preserveExistingBestRecords()
        XCTAssertEqual(data.recordWorkouts?.first?.actualReps[move.id.uuidString], [20])
        XCTAssertEqual(data.exerciseRecords()[key]?.bestSet?.value, 30)
        XCTAssertEqual(data.exerciseRecords()[key]?.bestDay?.value, 55)
        data.recordWorkouts = data.recordWorkouts?.map(\.bestRecordSnapshot)
        data.workouts.removeAll()
        XCTAssertEqual(data.exerciseRecords()[key]?.bestSet?.value, 30)
        XCTAssertEqual(data.exerciseRecords()[key]?.bestDay?.value, 55)
    }

    func testConcurrentWidgetUndoDoesNotRetainTypedEntryFromCancelledCompletion() {
        var base = started()
        var shortMove = move
        shortMove.sets = 1
        let other = Exercise(name: "풀업", sets: 1, detail: "10회")
        base.activeWorkout?.plan.exercises = [shortMove, other]
        base.changeSets(shortMove.id, by: 1, on: day, actualReps: 10, at: day)
        var widget = base
        widget.completeSetFromWidget(shortMove.id, now: day)
        var edited = base
        edited.changeSets(shortMove.id, by: -1, on: day, at: day)
        let entry = RecordEntry(typeID: "pushup", date: day, value: 99)
        edited.changeSets(shortMove.id, by: 1, on: day, actualReps: 99, at: day, recordEntry: entry)
        XCTAssertTrue(edited.finishWorkout(at: day))
        let merged = widget.applyingEdits(from: base, to: edited)
        XCTAssertEqual(merged.workouts.last?.done, 0)
        XCTAssertFalse(merged.records.contains { $0.id == entry.id }, "동시 완료 취소로 제거된 세트는 종목 기록도 남기지 않음")
        XCTAssertEqual(merged.exerciseRecords()[key]?.bestSet?.value, 20)
    }
}
