import XCTest
@testable import GymNote

/// 실행 탭 흐름: 순서 바꾸기·완료 운동 하단 표시·진행 기록 보존·재실행·종료 표시·저장 실패.
@MainActor
final class WorkoutFlowTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        SharedStore.testingDirectory = folder
    }

    override func tearDown() async throws {
        SharedStore.testingDirectory = nil
        try FileManager.default.removeItem(at: folder)
    }

    private let a = Exercise(name: "스쿼트", sets: 2, detail: "10회")
    private let b = Exercise(name: "푸쉬업", sets: 1, detail: "12회")
    private let c = Exercise(name: "플랭크", sets: 1, detail: "1분")

    private func makeModel() -> AppModel {
        let model = AppModel()
        var data = AppData(week: [])
        data.scheduledPlans[DayKey.key()] = DayPlan(title: "전신", exercises: [a, b, c])
        model.data = data
        return model
    }

    private func names(_ model: AppModel) -> [String] {
        model.data.executionExercises(on: model.workoutDate).map(\.name)
    }

    /// 다른 화면이 저장소 선택을 바꾼 것처럼 만들어 다음 저장을 실패시킨다(원본은 유지).
    private func breakPersistence() throws {
        _ = try SharedStore.activate(userID: UUID())
    }

    func testEditorSaveFailurePreservesLibraryAndPlanTogether() throws {
        let model = makeModel()
        let before = model.data
        let exercise = Exercise(name: "새 운동", sets: 3, detail: "10회")
        try breakPersistence()
        XCTAssertFalse(model.saveEdit { data in
            data.exerciseLibrary.append(exercise)
            data.scheduledPlans[DayKey.key()]?.exercises.append(exercise)
        })
        XCTAssertEqual(model.data, before, "저장 실패는 개인 목록과 계획을 모두 보존")
        XCTAssertNotNil(model.storageError)
    }

    func testEditorSaveSuccessIsPersistedAndCanBeRetriedAfterFailure() async throws {
        let model = makeModel()
        let item = DailyItem(title: "독서", scheduledDate: Date())
        let originalSelection = model.selection
        try breakPersistence()
        XCTAssertFalse(model.saveEdit { $0.saveDailyItemEditing(item) })
        XCTAssertFalse(model.data.dailyItems.contains { $0.id == item.id })
        // Re-select through the model so it receives the fresh generation. A plain reload
        // must not authorize writes using the stale selection from before the switch.
        try await model.switchAccount(originalSelection.userID)
        XCTAssertEqual(model.selection.userID, originalSelection.userID)
        XCTAssertNotEqual(model.selection.generation, originalSelection.generation)
        XCTAssertTrue(model.saveEdit { $0.saveDailyItemEditing(item) })
        XCTAssertTrue(try SharedStore.snapshot(userID: originalSelection.userID).data.dailyItems.contains { $0.id == item.id })
    }

    func testDayChangeRefreshesIdlePlanAndPreservesActiveWorkout() throws {
        let firstDay = try XCTUnwrap(DayKey.date(fromKey: "2026-10-10"))
        let nextDay = try XCTUnwrap(DayKey.date(fromKey: "2026-10-11"))
        var data = AppData.empty
        let firstPlan = DayPlan(title: "첫날", exercises: [a])
        let nextPlan = DayPlan(title: "다음날", exercises: [b])
        data.scheduledPlans[DayKey.key(firstDay)] = firstPlan
        data.scheduledPlans[DayKey.key(nextDay)] = nextPlan
        let model = AppModel(previewData: data)
        model.refreshCurrentDate(now: firstDay)
        XCTAssertEqual(model.todayPlan, firstPlan)
        model.refreshCurrentDate(now: nextDay)
        XCTAssertEqual(model.todayPlan, nextPlan)
        model.data.activeWorkout = WorkoutSession(startedAt: firstDay, plan: firstPlan)
        model.refreshCurrentDate(now: nextDay)
        XCTAssertEqual(model.todayPlan, firstPlan, "자정이 지나도 진행 중인 운동은 시작한 날의 계획 유지")
        XCTAssertEqual(model.workoutDate, firstDay)
    }

    func testMonthSelectionClampsDayAndKeepsWeekInsideNewMonth() throws {
        for (selected, target, expected) in [
            ("2024-01-31", "2024-02-01", "2024-02-29"),
            ("2026-01-31", "2026-02-01", "2026-02-28"),
            ("2026-10-10", "2026-11-01", "2026-11-10"),
            ("2026-12-31", "2027-01-01", "2027-01-31")
        ] {
            let date = DayKey.date(inMonth: try XCTUnwrap(DayKey.date(fromKey: target)),
                                   selectingDayOf: try XCTUnwrap(DayKey.date(fromKey: selected)))
            XCTAssertEqual(DayKey.key(date), expected)
            XCTAssertTrue(DayKey.weekDates(containing: date).contains { DayKey.key($0) == expected })
        }
    }

    func testReorderKeepsProgressAndSurvivesRelaunch() throws {
        let model = makeModel()
        model.startWorkout()
        model.completeSet(a, actualReps: 9)
        model.completeSet(b, actualReps: 11)
        let before = try XCTUnwrap(model.data.activeWorkout)
        XCTAssertEqual(names(model), ["스쿼트", "플랭크", "푸쉬업"], "완료한 운동은 아래")

        // 끌어서 맨 끝(완료 운동 위)으로, 다시 맨 위로.
        model.moveExecutionExercises(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(names(model), ["플랭크", "스쿼트", "푸쉬업"])
        model.moveExecutionExercise(a.id, .top)
        model.moveExecutionExercise(a.id, .down)
        XCTAssertEqual(names(model), ["플랭크", "스쿼트", "푸쉬업"])

        let after = try XCTUnwrap(model.data.activeWorkout)
        XCTAssertEqual(after.id, before.id)
        XCTAssertEqual(after.completedSets, before.completedSets, "세트 진행 그대로")
        XCTAssertEqual(after.actualReps, before.actualReps, "실제 횟수 그대로")
        XCTAssertEqual(after.actualWeights, before.actualWeights)
        XCTAssertTrue(model.data.workouts.isEmpty, "순서 변경은 일지를 만들지 않음")

        let saved = try SharedStore.snapshot(userID: nil).data
        XCTAssertEqual(saved.activeWorkout, after, "순서가 기기에 저장됨")
        let relaunched = AppModel()
        relaunched.reload()
        XCTAssertEqual(names(relaunched), ["플랭크", "스쿼트", "푸쉬업"], "재실행 후 순서 유지")
        XCTAssertEqual(relaunched.workoutProgress.done, 2)

        // 완료 취소하면 푸쉬업은 원래 자리(두 번째 저장 위치)로 돌아온다.
        relaunched.undoSet(b)
        XCTAssertEqual(names(relaunched), ["플랭크", "푸쉬업", "스쿼트"])
    }

    func testReorderFailureKeepsPreviousOrder() throws {
        let model = makeModel()
        model.startWorkout()
        let session = try XCTUnwrap(model.data.activeWorkout)
        try breakPersistence()
        model.moveExecutionExercises(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(model.data.activeWorkout, session, "저장 실패 시 이전 순서로 되돌림")
        XCTAssertNotNil(model.storageError)
    }

    func testFinishShowsSavedOnlyAfterRealSave() throws {
        let model = makeModel()
        model.startWorkout()
        model.completeSet(a, actualReps: 10)
        XCTAssertNotNil(model.restEnd, "세트 완료 후 휴식")
        XCTAssertTrue(model.finishWorkout())
        let saved = try XCTUnwrap(model.savedWorkout)
        XCTAssertNil(model.data.activeWorkout)
        XCTAssertNil(model.restEnd, "저장 후 휴식 정리")
        XCTAssertEqual(saved.done, 1)
        XCTAssertEqual(try SharedStore.snapshot(userID: nil).data.workouts.map(\.id), [saved.id], "기기에 실제 저장")

        // 빠르게 새 운동을 시작하면 종료 표시를 거둔다.
        model.startWorkout()
        XCTAssertNotNil(model.data.activeWorkout)
        XCTAssertNil(model.savedWorkout)
    }

    func testFinishFailureKeepsActiveWorkoutAndRest() throws {
        let model = makeModel()
        model.startWorkout()
        model.completeSet(a, actualReps: 10)
        let session = try XCTUnwrap(model.data.activeWorkout)
        let restEnd = try XCTUnwrap(model.restEnd)
        try breakPersistence()
        XCTAssertFalse(model.finishWorkout())
        XCTAssertEqual(model.data.activeWorkout, session, "진행 중 운동 유지")
        XCTAssertEqual(model.restEnd, restEnd, "휴식 타이머 유지")
        XCTAssertNil(model.savedWorkout, "저장 완료를 표시하지 않음")
        XCTAssertTrue(model.data.workouts.isEmpty)
        XCTAssertNotNil(model.storageError)
    }

    func testZeroSetCancelDoesNotShowSaved() throws {
        let model = makeModel()
        model.startWorkout()
        XCTAssertFalse(model.finishWorkout(), "0세트는 시작 취소")
        XCTAssertNil(model.data.activeWorkout)
        XCTAssertNil(model.savedWorkout)
        XCTAssertTrue(model.data.workouts.isEmpty)
    }

    func testAutomaticLastSetShowsSavedAndStopsRest() throws {
        let model = makeModel()
        model.startWorkout()
        model.completeSet(a, actualReps: 10)
        model.completeSet(a, actualReps: 10)
        model.completeSet(b, actualReps: 12)
        XCTAssertNotNil(model.restEnd)
        model.completeSet(c)
        XCTAssertNil(model.data.activeWorkout, "마지막 세트로 자동 저장")
        XCTAssertNil(model.restEnd, "자동 저장 후 휴식은 켜지 않음")
        XCTAssertEqual(model.savedWorkout?.done, 4)
        XCTAssertEqual(model.data.workouts.count, 1)
    }

    func testAutomaticLastSetFailureKeepsWorkout() throws {
        let model = makeModel()
        model.startWorkout()
        model.completeSet(a)
        model.completeSet(a)
        model.completeSet(b)
        let session = try XCTUnwrap(model.data.activeWorkout)
        let restEnd = try XCTUnwrap(model.restEnd)
        try breakPersistence()
        model.completeSet(c)
        XCTAssertEqual(model.data.activeWorkout, session, "저장 실패 시 마지막 세트 전 상태 유지")
        XCTAssertEqual(model.restEnd, restEnd, "실패한 세트는 기존 휴식 시간을 다시 시작하지 않음")
        XCTAssertNil(model.savedWorkout)
    }

    func testFailedSetDoesNotStartRest() throws {
        let model = makeModel()
        model.startWorkout()
        let session = try XCTUnwrap(model.data.activeWorkout)
        try breakPersistence()
        model.completeSet(a, actualReps: 10)
        XCTAssertEqual(model.data.activeWorkout, session, "저장 실패한 세트는 기록하지 않음")
        XCTAssertNil(model.restEnd, "기록되지 않은 세트로 휴식을 시작하지 않음")
        XCTAssertNotNil(model.storageError)
    }

    func testAccountSwitchClearsSavedWorkout() async throws {
        let model = makeModel()
        model.startWorkout()
        model.completeSet(a)
        XCTAssertTrue(model.finishWorkout())
        XCTAssertNotNil(model.savedWorkout)
        try await model.switchAccount(UUID())
        XCTAssertNil(model.savedWorkout, "계정 전환 시 이전 계정 표시를 남기지 않음")
    }

    func testRecordEntryFromExecutionTab() throws {
        let model = makeModel()
        let types = model.account.catalogTypes.filter(\.active)
        let count = try XCTUnwrap(types.first { $0.recordType.style == .count })
        let rounds = try XCTUnwrap(types.first { $0.recordType.style == .rounds })

        XCTAssertEqual(model.saveRecord(RecordEntry(typeID: count.id, date: Date(), value: 20)), .newBest)
        XCTAssertEqual(model.saveRecord(RecordEntry(typeID: count.id, date: Date(), value: 15)), .saved,
                       "최고 기록보다 낮아도 저장")
        XCTAssertEqual(model.saveRecord(RecordEntry(typeID: rounds.id, date: Date(), value: 5, extraReps: 3)), .newBest)
        XCTAssertEqual(model.data.records.count, 3)
        XCTAssertEqual(model.saveRecord(RecordEntry(typeID: count.id, date: Date(), value: 1.5)), .rejected,
                       "횟수는 정수만")
        XCTAssertEqual(model.saveRecord(RecordEntry(typeID: "없는 종목", date: Date(), value: 1)), .rejected)
        XCTAssertEqual(model.data.records.count, 3)
        model.storageError = nil

        try breakPersistence()
        XCTAssertEqual(model.saveRecord(RecordEntry(typeID: count.id, date: Date(), value: 30)), .rejected,
                       "저장 실패는 저장됨으로 표시하지 않음")
        XCTAssertEqual(model.data.records.count, 3)
    }
}
