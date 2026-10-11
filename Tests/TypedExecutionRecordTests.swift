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
        let exercise = Exercise(name: type.name, sets: sets, detail: type.style == .rounds ? "1라운드" : "")
        var data = AppData.empty
        data.recordTypes.append(type)
        data.preserveExistingBestRecords()
        data.scheduledPlans[DayKey.key(date)] = DayPlan(title: "측정 운동", exercises: [exercise])
        XCTAssertTrue(data.startWorkout(at: date))
        return (data, exercise)
    }

    func testTodayExecutionSavesRoundsAndExtraRepetitions() throws {
        let model = AppModel()
        let definition = try XCTUnwrap(model.account.catalogTypes.first { $0.style == .rounds })
        var exercise = definition.makeExercise()
        exercise.sets = 1
        var data = AppData.empty
        data.recordTypes.append(definition.recordType)
        let previous = RecordEntry(typeID: definition.id, date: Date().addingTimeInterval(-86400), value: 5, extraReps: 2)
        data.records = [previous]
        data.bestRecordEntries = [previous] // Existing baseline, before the execution under test.
        data.scheduledPlans[DayKey.key()] = DayPlan(title: "신디", exercises: [exercise])
        model.data = data

        model.startWorkout(catalog: model.account.catalogTypes)
        model.completeSet(exercise, measurement: 5, extraReps: 3)

        XCTAssertNil(model.data.activeWorkout)
        XCTAssertEqual(model.data.workouts.count, 1)
        XCTAssertEqual(model.data.records.count, 2)
        XCTAssertTrue(model.data.records.contains(previous))
        let best = try XCTUnwrap(model.data.best(definition.recordType))
        XCTAssertEqual(best.value, 5)
        XCTAssertEqual(best.extraReps, 3)
        XCTAssertEqual(DayKey.key(best.date), DayKey.key())
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
