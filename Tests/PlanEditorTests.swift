import XCTest
@testable import GymNote

@MainActor
final class PlanEditorTests: XCTestCase {
    private var folder: URL!
    private var model: AppModel!
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        SharedStore.testingDirectory = folder
        model = AppModel()
        model.account = AccountModel(model: model, client: nil, initialConnection: .offline, monitorConnectivity: false)
        let a = CatalogRecordType.defaults[0].makeExercise()
        let b = CatalogRecordType.defaults[1].makeExercise()
        model.data.scheduledPlans[DayKey.key(date)] = DayPlan(title: "원래 계획", exercises: [a, b])
    }

    override func tearDown() async throws {
        model = nil
        SharedStore.testingDirectory = nil
        try FileManager.default.removeItem(at: folder)
    }

    func testDeleteUndoRestoresOnlyItsDateAndPersists() throws {
        let session = PlanEditorSession(model: model, date: date)
        let before = session.plan
        session.remove(before.exercises[0])
        XCTAssertEqual(session.plan.exercises, [before.exercises[1]])
        XCTAssertTrue(session.canUndo)
        let anotherDate = date.addingTimeInterval(86400)
        model.data.scheduledPlans[DayKey.key(anotherDate)] = DayPlan(title: "다른 날짜 변경", exercises: [])
        session.undoDeletion()
        XCTAssertEqual(session.plan, before)
        XCTAssertEqual(model.data.plan(for: anotherDate).title, "다른 날짜 변경")
        XCTAssertEqual(try SharedStore.snapshot(userID: nil).data.plan(for: date), before)
    }

    func testLaterPlanEditPreventsStaleUndo() {
        let session = PlanEditorSession(model: model, date: date)
        session.remove(session.plan.exercises[0])
        model.data.scheduledPlans[DayKey.key(date)]?.title = "다른 화면에서 수정"
        let changed = session.plan
        XCTAssertFalse(session.canUndo)
        session.undoDeletion()
        XCTAssertEqual(session.plan, changed)
        XCTAssertNotNil(session.failure)
    }

    func testFailedDeletionRenameMoveAndReplacementPreserveOriginal() throws {
        let session = PlanEditorSession(model: model, date: date)
        let before = model.data
        _ = try SharedStore.activate(userID: UUID())
        session.remove(session.plan.exercises[0])
        XCTAssertNil(session.deletion)
        XCTAssertFalse(session.rename("저장 실패한 이름"))
        session.move(from: IndexSet(integer: 0), to: 2)
        XCTAssertFalse(session.replace(with: DayPlan(title: "새 계획", exercises: [CatalogRecordType.defaults[2].makeExercise()])))
        XCTAssertEqual(model.data, before)
        XCTAssertNotNil(session.failure)
    }

    func testFailedUndoKeepsTokenForRetry() throws {
        let session = PlanEditorSession(model: model, date: date)
        session.remove(session.plan.exercises[0])
        let afterDelete = model.data
        _ = try SharedStore.activate(userID: UUID())
        session.undoDeletion()
        XCTAssertEqual(model.data, afterDelete)
        XCTAssertNotNil(session.deletion)
        XCTAssertTrue(session.canUndo)
        XCTAssertNotNil(session.failure)
    }

    func testGenerationChangeRejectsAllOldEditorActions() async throws {
        let session = PlanEditorSession(model: model, date: date)
        let exercise = session.plan.exercises[0]
        try await model.switchAccount(nil)
        let afterSwitch = model.data
        XCTAssertFalse(session.isCurrentOwner, "古いエディタから基本ルーチンを開くことも禁止")
        XCTAssertFalse(session.rename("이전 화면 이름"))
        XCTAssertFalse(session.add(exercise))
        XCTAssertFalse(session.replace(with: DayPlan(title: "이전 화면 교체", exercises: [exercise])))
        session.remove(exercise)
        session.move(from: IndexSet(integer: 0), to: 1)
        XCTAssertEqual(model.data, afterSwitch)
        XCTAssertNotNil(session.failure)
    }

    func testMoveAndRenamePersistWithoutChangingJournal() throws {
        let plan = model.data.plan(for: date)
        let workout = WorkoutSession(startedAt: date, plan: plan, completedSets: [plan.exercises[0].id.uuidString: 1])
        model.data.workouts = [workout]
        let session = PlanEditorSession(model: model, date: date)
        session.move(from: IndexSet(integer: 0), to: 2)
        XCTAssertEqual(session.plan.exercises, Array(plan.exercises.reversed()))
        XCTAssertTrue(session.rename("수정한 이름"))
        XCTAssertEqual(try SharedStore.snapshot(userID: nil).data.plan(for: date).title, "수정한 이름")
        XCTAssertEqual(model.data.workouts, [workout])
    }

    func testEmptyReplacementIsRejectedAndLibraryTemplateStaysIndependent() {
        let session = PlanEditorSession(model: model, date: date)
        let before = model.data
        XCTAssertFalse(session.replace(with: DayPlan(title: "휴식", exercises: [])))
        XCTAssertEqual(model.data, before)
        var template = CatalogRecordType.defaults[0].makeExercise()
        template.applySetReps([12, 10, 8])
        model.data.exerciseLibrary = [template]
        var copy = template
        copy.id = UUID()
        XCTAssertTrue(session.add(copy))
        XCTAssertEqual(session.plan.exercises.last?.setReps, [12, 10, 8])
        XCTAssertEqual(model.data.exerciseLibrary, [template])
        XCTAssertNotEqual(session.plan.exercises.last?.id, template.id)
    }

    func testActiveWorkoutBlocksPlanChangesAndKeepsSessionSnapshot() {
        let plan = model.data.plan(for: date)
        model.data.activeWorkout = WorkoutSession(startedAt: date, plan: plan)
        let before = model.data
        let session = PlanEditorSession(model: model, date: date)
        XCTAssertFalse(session.rename("진행 중 수정"))
        XCTAssertFalse(session.add(plan.exercises[0]))
        session.remove(plan.exercises[0])
        XCTAssertEqual(model.data, before)
    }
}
