import XCTest
@testable import GymNote

@MainActor
final class RegisteredWorkoutCleanupTests: XCTestCase {
    private var folder: URL!
    private let allowed = CatalogRecordType.defaults[0]

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        SharedStore.testingDirectory = folder
    }

    override func tearDown() async throws {
        SharedStore.testingDirectory = nil
        try FileManager.default.removeItem(at: folder)
    }

    private func mixedData() -> AppData {
        let keep = Exercise(name: allowed.name, sets: 2, detail: "10회")
        let remove = Exercise(name: "미등록 운동", sets: 2, detail: "20회")
        let plan = DayPlan(title: "혼합", exercises: [keep, remove])
        var session = WorkoutSession(startedAt: Date(), plan: plan)
        for exercise in plan.exercises {
            let key = exercise.id.uuidString
            session.completedSets[key] = 1
            session.actualReps[key] = [10]
            session.actualWeights[key] = [5]
            session.recordReps[key] = [10]
            session.recordEntries[key] = [RecordEntry(typeID: exercise.id == keep.id ? allowed.id : "removed", date: Date(), value: 10)]
            session.recordTotals[key] = 10
        }
        var data = AppData.empty
        data.week[1] = plan
        data.scheduledPlans[DayKey.key()] = plan
        data.exerciseLibrary = plan.exercises
        data.activeWorkout = session
        data.workouts = [session]
        data.recordWorkouts = [session]
        data.recordTypes = [RecordType.defaults[0], allowed.recordType, RecordType(id: "removed", name: remove.name)]
        data.records = [RecordEntry(typeID: "pushup", date: Date(), value: 11),
                        RecordEntry(typeID: allowed.id, date: Date(), value: 12),
                        RecordEntry(typeID: "removed", date: Date(), value: 99),
                        RecordEntry(typeID: "unknown", date: Date(), value: 999)]
        data.bestRecordEntries = data.records
        data.logs = [DayLog(day: DayKey.key(), doneSets: session.completedSets)]
        return data
    }

    private func assertOnlyRegistered(_ data: AppData, file: StaticString = #filePath, line: UInt = #line) {
        let plans = data.week + Array(data.scheduledPlans.values)
            + data.workouts.map(\.plan) + (data.recordWorkouts ?? []).map(\.plan)
            + (data.activeWorkout.map { [$0.plan] } ?? [])
        XCTAssertTrue(plans.flatMap(\.exercises).allSatisfy { $0.name == allowed.name }, file: file, line: line)
        XCTAssertTrue(data.exerciseLibrary.allSatisfy { $0.name == allowed.name }, file: file, line: line)
        XCTAssertTrue(data.recordTypes.allSatisfy { $0.name == allowed.name }, file: file, line: line)
        XCTAssertTrue((data.records + (data.bestRecordEntries ?? [])).allSatisfy {
            $0.typeID == allowed.id || $0.typeID == "pushup"
        }, file: file, line: line)
        for session in data.workouts + (data.recordWorkouts ?? []) + (data.activeWorkout.map { [$0] } ?? []) {
            let keys = Set(session.plan.exercises.map { $0.id.uuidString })
            for actual in [Set(session.completedSets.keys), Set(session.actualReps.keys),
                           Set(session.actualWeights.keys), Set(session.recordReps.keys),
                           Set(session.recordEntries.keys), Set(session.recordTotals.keys)] {
                XCTAssertTrue(actual.isSubset(of: keys), file: file, line: line)
            }
        }
    }

    func testMixedPlanDeletesEveryReferenceAndPreservesRegisteredLegacyRecords() throws {
        let original = mixedData()
        let result = original.removingUnregisteredWorkouts(catalog: [allowed])
        assertOnlyRegistered(result)
        XCTAssertEqual(result.week.count, 7)
        XCTAssertEqual(result.scheduledPlans[DayKey.key()]?.exercises, [original.week[1].exercises[0]])
        XCTAssertEqual(result.records.map(\.id), Array(original.records.prefix(2)).map(\.id))
        XCTAssertEqual(result.bestRecordEntries?.map(\.id), Array(original.records.prefix(2)).map(\.id))
        XCTAssertEqual(result.activeWorkout?.id, original.activeWorkout?.id)
        XCTAssertEqual(result.activeWorkout?.done, 1)
        XCTAssertEqual(result.activeWorkout?.total, 2)
        XCTAssertEqual(result.logs.first?.doneSets, [original.week[1].exercises[0].id.uuidString: 1])
        XCTAssertEqual(original.week[1].exercises.count, 2, "순수 정리는 입력을 변경하지 않음")
        XCTAssertEqual(result.removingUnregisteredWorkouts(catalog: [allowed]), result)
    }

    func testEmptyVerifiedCatalogDeletesAllWorkoutHistoryButKeepsExplicitRestDate() {
        let original = mixedData()
        let result = original.removingUnregisteredWorkouts(catalog: [])
        XCTAssertTrue(result.week.allSatisfy(\.isRestDay))
        XCTAssertNotNil(result.scheduledPlans[DayKey.key()])
        XCTAssertTrue(result.scheduledPlans[DayKey.key()]!.isRestDay)
        XCTAssertNil(result.activeWorkout)
        XCTAssertTrue(result.workouts.isEmpty)
        XCTAssertTrue(result.recordWorkouts?.isEmpty == true)
        XCTAssertTrue(result.recordTypes.isEmpty)
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertTrue(result.bestRecordEntries?.isEmpty == true)
        XCTAssertTrue(result.exerciseLibrary.isEmpty)
        XCTAssertTrue(result.logs.allSatisfy { $0.doneSets.isEmpty })
    }

    func testInactiveCatalogDefinitionCannotKeepExistingWorkout() {
        var inactive = allowed
        inactive.active = false
        let original = mixedData()
        XCTAssertEqual(original.removingUnregisteredWorkouts(catalog: [inactive]),
                       original.removingUnregisteredWorkouts(catalog: []))
    }

    func testAllUnregisteredPlanBecomesRestWithoutRestoringWeeklyFallback() {
        var data = mixedData()
        let removed = data.week[1].exercises[1]
        data.scheduledPlans[DayKey.key()] = DayPlan(title: "미등록만", exercises: [removed])
        data.activeWorkout = WorkoutSession(startedAt: Date(), plan: data.scheduledPlans[DayKey.key()]!)
        let cleaned = data.removingUnregisteredWorkouts(catalog: [allowed])
        XCTAssertNil(cleaned.activeWorkout)
        XCTAssertTrue(cleaned.plan(for: Date()).isRestDay)
        XCTAssertEqual(cleaned.week[1].exercises.count, 1, "주간 계획과 명시적 날짜 휴식은 별개")
    }

    func testRegisteredExerciseCannotRetainUnregisteredMeasuredEntry() throws {
        var original = mixedData()
        let key = original.week[1].exercises[0].id.uuidString
        original.activeWorkout!.recordEntries[key] = [RecordEntry(typeID: "unknown", date: Date(), value: 999)]
        let cleaned = original.removingUnregisteredWorkouts(catalog: [allowed])
        XCTAssertEqual(cleaned.activeWorkout?.recordEntries[key]?.count, 1)
        XCTAssertNil(cleaned.activeWorkout?.recordEntries[key]?[0])
        XCTAssertEqual(cleaned.activeWorkout?.done, 1)
    }

    func testCleanupPreservesDailyDataAndSettings() {
        var original = mixedData()
        original.defaultRest = 125
        original.restStep = 25
        original.restSound = true
        let item = DailyItem(title: "물 마시기")
        original.dailyItems = [item]
        original.dailyCompletions = [DailyCompletion(itemID: item.id, title: item.title, note: "보존",
                                                     kind: item.kind, day: DayKey.key(), completedAt: Date())]
        original.dailyReminders.morningSummary = ReminderTime(hour: 8, minute: 30)
        let result = original.removingUnregisteredWorkouts(catalog: [allowed])
        XCTAssertEqual(result.dailyItems, original.dailyItems)
        XCTAssertEqual(result.dailyCompletions, original.dailyCompletions)
        XCTAssertEqual(result.dailyReminders, original.dailyReminders)
        XCTAssertEqual(result.defaultRest, 125)
        XCTAssertEqual(result.restStep, 25)
        XCTAssertTrue(result.restSound)
    }

    func testVerifiedCleanupRestoresWorkoutStartForMixedExistingPlan() throws {
        var existing = mixedData()
        existing.activeWorkout = nil
        existing.workouts = []
        existing.logs = []
        let model = AppModel(previewData: existing)
        model.startWorkout(catalog: [allowed])
        XCTAssertNil(model.data.activeWorkout, "정리 전에는 미등록 종목이 운동 시작을 막음")
        try model.applyVerifiedWorkoutCatalog([allowed])
        model.startWorkout(catalog: [allowed])
        let session = try XCTUnwrap(model.data.activeWorkout)
        XCTAssertEqual(session.plan.exercises, [existing.week[1].exercises[0]])
        XCTAssertEqual(session.done, 0)
        XCTAssertEqual(session.total, 2)
    }

    func testVerifiedPolicyCleansStoreAndRejectsSubsequentUnregisteredEdits() throws {
        let selection = try SharedStore.activate(userID: nil)
        let initial = try SharedStore.snapshot(userID: nil).data
        _ = try SharedStore.persistEdits(from: initial, to: mixedData(), selection: selection)
        try SharedStore.saveRecordCatalog(RecordCatalogCache(project: "test", types: [allowed], fetchedAt: Date()))
        let cleaned = try SharedStore.useVerifiedWorkoutCatalog([allowed], selection: selection)
        assertOnlyRegistered(cleaned)
        let result = try SharedStore.persistEdits(from: cleaned, to: mixedData(), selection: selection)
        assertOnlyRegistered(result)
        assertOnlyRegistered(try SharedStore.snapshot(userID: nil).data)
        assertOnlyRegistered(SharedStore.widgetSnapshot().0)
    }

    func testStoreReadsSanitizeLegacyWriterAndKeepRecoveryCopy() throws {
        let selection = try SharedStore.activate(userID: nil)
        _ = try SharedStore.useVerifiedWorkoutCatalog([allowed], selection: selection)
        let incoming = StoredWorkout(data: mixedData())
        try JSONEncoder().encode(incoming).write(to: folder.appendingPathComponent(SharedStore.fileName))
        let cleaned = try SharedStore.snapshot(userID: nil)
        assertOnlyRegistered(cleaned.data)
        XCTAssertTrue(cleaned.dirty)
        let backup = folder.appendingPathComponent("backup-guest-registered-workouts.json")
        let preserved = try JSONDecoder().decode(StoredWorkout.self, from: Data(contentsOf: backup))
        XCTAssertEqual(preserved.data, incoming.data)
        XCTAssertEqual(try SharedStore.snapshot(userID: nil).revision, cleaned.revision, "재조회는 정리를 반복 저장하지 않음")
    }

    func testCloudReplacementAndMergeCannotReintroduceRemovedHistory() throws {
        let selection = try SharedStore.activate(userID: UUID())
        _ = try SharedStore.useVerifiedWorkoutCatalog([allowed], selection: selection)
        let remote = mixedData()
        let before = try SharedStore.snapshot(userID: selection.userID)
        try SharedStore.replaceWithCloud(remote, version: 1, revision: before.revision, selection: selection)
        let cleaned = try SharedStore.snapshot(userID: selection.userID)
        assertOnlyRegistered(cleaned.data)
        XCTAssertTrue(cleaned.dirty, "정리된 삭제를 서버로 올려야 함")
        var nextRemote = remote
        nextRemote.defaultRest = 130
        XCTAssertTrue(try SharedStore.mergeWithCloud(nextRemote, version: 2, selection: selection))
        let merged = try SharedStore.snapshot(userID: selection.userID)
        assertOnlyRegistered(merged.data)
        XCTAssertEqual(merged.data.defaultRest, 130)
        XCTAssertTrue(merged.dirty)
    }

    func testGuestImportAndAccountSwitchKeepPolicy() throws {
        let guest = try SharedStore.activate(userID: nil)
        let initial = try SharedStore.snapshot(userID: nil).data
        _ = try SharedStore.persistEdits(from: initial, to: mixedData(), selection: guest)
        let account = try SharedStore.activate(userID: UUID())
        try SharedStore.saveRecordCatalog(RecordCatalogCache(project: "test", types: [allowed], fetchedAt: Date()))
        _ = try SharedStore.useVerifiedWorkoutCatalog([allowed], selection: account)
        try SharedStore.importGuest(selection: account)
        assertOnlyRegistered(try SharedStore.snapshot(userID: account.userID).data)
        _ = try SharedStore.activate(userID: nil)
        assertOnlyRegistered(try SharedStore.snapshot(userID: nil).data)
        _ = try SharedStore.activate(userID: UUID())
        assertOnlyRegistered(SharedStore.widgetSnapshot().0)
    }
}
