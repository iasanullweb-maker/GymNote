import XCTest
@testable import GymNote

final class LegacyRecordBaselineTests: XCTestCase {
    private let day = Calendar.current.startOfDay(for: Date()).addingTimeInterval(3600)

    private func baseline() -> AppData {
        var data = AppData.empty
        data.records = [RecordEntry(typeID: data.recordTypes[0].id, date: day.addingTimeInterval(-86400), value: 20)]
        data.preserveExistingBestRecords()
        return data
    }

    func testLegacyCloudManualEditKeepsBestButPreservesEditedPhysicalRecord() throws {
        let base = baseline()
        var remote = base
        remote.records[0].value = 100
        remote.bestRecordEntries = nil
        remote.recordWorkouts = nil
        var local = base
        local.restStep = base.restStep + 5
        let merged = try XCTUnwrap(remote.mergingCloud(local: local, base: base))
        XCTAssertEqual(merged.records[0].value, 100)
        XCTAssertEqual(merged.restStep, local.restStep)
        XCTAssertEqual(merged.best(base.recordTypes[0])?.value, 20)
    }

    func testLegacyCloudNewManualEntryCannotEstablishNewBest() throws {
        let base = baseline()
        var remote = base
        let incoming = RecordEntry(typeID: base.recordTypes[0].id, date: day, value: 100)
        remote.records.append(incoming)
        remote.bestRecordEntries = nil
        remote.recordWorkouts = nil
        let merged = try XCTUnwrap(remote.mergingCloud(local: base, base: base))
        XCTAssertTrue(merged.records.contains(incoming), "구버전 원본 기록도 데이터에서 보존")
        XCTAssertEqual(merged.best(base.recordTypes[0])?.value, 20)
    }

    func testTodaysExecutionTypedMeasurementUpdatesPreservedBest() {
        var data = baseline()
        let current = CatalogRecordType.defaults[0]
        let exercise = Exercise(name: current.name, sets: 1, detail: "10회")
        data.recordTypes.append(current.recordType)
        data.scheduledPlans[DayKey.key(day)] = DayPlan(title: "오늘", exercises: [exercise])
        XCTAssertTrue(data.startWorkout(at: day))
        let entry = RecordEntry(typeID: current.id, date: day, value: 25)
        data.changeSets(exercise.id, by: 1, on: day, actualReps: 25, at: day, recordEntry: entry)
        XCTAssertNil(data.activeWorkout)
        XCTAssertEqual(data.best(current.recordType)?.value, 25)
        XCTAssertEqual(data.recordProjection(catalog: [current]).best(current.recordType)?.value, 25)
        XCTAssertTrue(data.records.contains(entry))
    }

    func testProjectionMapsFrozenLegacyIDsWithoutPromotingPhysicalEdit() {
        var data = baseline()
        let oldID = data.records[0].typeID
        data.records[0].value = 100
        let current = CatalogRecordType.defaults[0]
        let projected = data.recordProjection(catalog: [current])
        XCTAssertEqual(projected.best(current.recordType)?.value, 20)
        XCTAssertEqual(projected.entries(current.recordType).map(\.value), [20])
        XCTAssertEqual(data.records[0].typeID, oldID)
        XCTAssertEqual(data.records[0].value, 100)
    }
}
