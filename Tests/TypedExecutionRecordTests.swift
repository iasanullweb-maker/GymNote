import XCTest
@testable import GymNote

@MainActor
final class TypedExecutionRecordTests: XCTestCase {
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

    private func startedData(type: RecordType, sets: Int = 1, on date: Date) -> (AppData, Exercise) {
        let exercise = Exercise(name: type.name, sets: sets, detail: type.style == .rounds ? "한 세트" : "")
        var data = AppData.empty
        data.recordTypes.append(type)
        data.preserveExistingBestRecords()
        data.scheduledPlans[DayKey.key(date)] = DayPlan(title: "측정 운동", exercises: [exercise])
        XCTAssertTrue(data.startWorkout(at: date))
        return (data, exercise)
    }

    func testRoundStyleExerciseCountsSetsWithoutRecord() throws {
        let model = AppModel()
        let definition = try XCTUnwrap(model.account.catalogTypes.first { $0.style == .rounds })
        var exercise = definition.makeExercise()
        XCTAssertEqual(exercise.detail, "한 세트", "신디는 라운드가 아니라 세트로 부른다")
        XCTAssertNil(exercise.plannedReps)
        exercise.sets = 2
        var data = AppData.empty
        data.recordTypes.append(definition.recordType)
        let previous = RecordEntry(typeID: definition.id, date: Date().addingTimeInterval(-86400), value: 5, extraReps: 2)
        data.records = [previous]
        data.bestRecordEntries = [previous] // Existing baseline, before the execution under test.
        data.scheduledPlans[DayKey.key()] = DayPlan(title: "신디", exercises: [exercise])
        model.data = data

        model.startWorkout(catalog: model.account.catalogTypes)
        model.completeSet(exercise)
        XCTAssertEqual(model.data.activeWorkout?.done, 1, "세트 완료만 눌러도 한 세트가 완료된다")
        // 예전 화면처럼 라운드 값을 넘겨도 기록하지 않고 세트로만 센다.
        model.completeSet(exercise, measurement: 9, extraReps: 3)

        XCTAssertNil(model.data.activeWorkout)
        XCTAssertEqual(model.data.workouts.count, 1)
        XCTAssertEqual(model.data.workouts.first?.done, 2)
        XCTAssertEqual(model.data.records, [previous], "실행에서는 신디 최고기록을 바꾸지 않는다")
        XCTAssertEqual(try XCTUnwrap(model.data.best(definition.recordType)), previous)
    }

    func testOldRoundPlanIsCalledOneSet() throws {
        var data = AppData.empty
        let old = Exercise(name: "신디", sets: 3, detail: "1라운드")
        data.scheduledPlans[DayKey.key()] = DayPlan(title: "신디", exercises: [old])
        data.exerciseLibrary = [old]
        let restored = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(restored.scheduledPlans[DayKey.key()]?.exercises.first?.detail, "한 세트")
        XCTAssertEqual(restored.exerciseLibrary.first?.detail, "한 세트")
        XCTAssertEqual(restored.scheduledPlans[DayKey.key()]?.exercises.first?.id, old.id, "진행 기록이 이어지도록 ID 유지")
    }

    func testPastSessionCompletedInExecutionDoesNotCreditMeasurement() throws {
        let model = AppModel()
        let definition = try XCTUnwrap(model.account.catalogTypes.first { $0.style == .rounds })
        var exercise = definition.makeExercise()
        exercise.sets = 1
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        var data = AppData.empty
        data.recordTypes.append(definition.recordType)
        data.scheduledPlans[DayKey.key(yesterday)] = DayPlan(title: "지난 운동", exercises: [exercise])
        XCTAssertTrue(data.startWorkout(at: yesterday))
        model.data = data

        model.completeSet(exercise, measurement: 99, extraReps: 1)

        XCTAssertNil(model.data.activeWorkout)
        XCTAssertEqual(model.data.workouts.count, 1)
        XCTAssertTrue(model.data.records.isEmpty)
        XCTAssertNil(model.data.best(definition.recordType))
    }

    func testSharedCompletionRetainsDecimalWeightAndExistingBest() throws {
        let date = Date()
        let type = RecordType(id: "weight", name: "벤치프레스", unit: "kg")
        var (data, exercise) = startedData(type: type, on: date)
        let previous = RecordEntry(typeID: type.id, date: date.addingTimeInterval(-86400), value: 20)
        let measurement = RecordEntry(typeID: type.id, date: date, value: 32.5)
        data.records = [previous]
        data.bestRecordEntries = [previous] // Existing baseline, before the execution under test.

        data.changeSets(exercise.id, by: 1, on: date, at: date, recordEntry: measurement)

        XCTAssertNil(data.activeWorkout)
        XCTAssertEqual(data.records.count, 2)
        XCTAssertTrue(data.records.contains(previous))
        XCTAssertTrue(data.records.contains(measurement))
        XCTAssertEqual(try XCTUnwrap(data.best(type)).value, 32.5)
    }

    func testSharedCompletionRetainsDecimalTimeAndLowerIsBetter() throws {
        let date = Date()
        let type = RecordType(id: "time", name: "달리기", unit: "초", lowerIsBetter: true)
        var (data, exercise) = startedData(type: type, on: date)
        let previous = RecordEntry(typeID: type.id, date: date.addingTimeInterval(-86400), value: 18.75)
        let measurement = RecordEntry(typeID: type.id, date: date, value: 16.25)
        data.records = [previous]
        data.bestRecordEntries = [previous] // Existing baseline, before the execution under test.

        data.changeSets(exercise.id, by: 1, on: date, at: date, recordEntry: measurement)

        XCTAssertEqual(data.records.count, 2)
        XCTAssertEqual(try XCTUnwrap(data.best(type)).value, 16.25)
    }

    func testSharedPastCompletionDoesNotAppendMeasuredRecord() {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let type = RecordType(id: "weight", name: "벤치프레스", unit: "kg")
        var (data, exercise) = startedData(type: type, on: yesterday)
        let measurement = RecordEntry(typeID: type.id, date: now, value: 80.5)

        data.changeSets(exercise.id, by: 1, on: yesterday, at: now, recordEntry: measurement)

        XCTAssertEqual(data.workouts.count, 1)
        XCTAssertTrue(data.records.isEmpty)
    }

    func testWidgetCreditFlagCannotAppendMeasuredRecord() {
        let date = Date()
        let type = RecordType(id: "weight", name: "벤치프레스", unit: "kg")
        var (data, exercise) = startedData(type: type, on: date)
        let measurement = RecordEntry(typeID: type.id, date: date, value: 80.5)

        data.changeSets(exercise.id, by: 1, on: date, at: date, creditRecords: false, recordEntry: measurement)

        XCTAssertEqual(data.workouts.count, 1)
        XCTAssertTrue(data.records.isEmpty)
    }

    func testUndoRemovesMeasuredCandidateAndPreservesEarlierRecord() throws {
        let date = Date()
        let type = RecordType(id: "rounds", name: "신디", unit: "", style: .rounds, repsPerRound: 30)
        var (data, exercise) = startedData(type: type, sets: 2, on: date)
        let previous = RecordEntry(typeID: type.id, date: date.addingTimeInterval(-86400), value: 2, extraReps: 1)
        let measurement = RecordEntry(typeID: type.id, date: date, value: 9, extraReps: 2)
        data.records = [previous]
        data.bestRecordEntries = [previous] // Existing baseline, before the execution under test.

        data.changeSets(exercise.id, by: 1, on: date, at: date, recordEntry: measurement)
        XCTAssertNotNil(data.activeWorkout)
        data.changeSets(exercise.id, by: -1, on: date, at: date)
        data.completeSetFromWidget(exercise.id, now: date)
        data.completeSetFromWidget(exercise.id, now: date)

        XCTAssertNil(data.activeWorkout)
        XCTAssertEqual(data.workouts.count, 1)
        XCTAssertEqual(data.records, [previous])
        XCTAssertEqual(try XCTUnwrap(data.best(type)).value, 2)
    }
}
