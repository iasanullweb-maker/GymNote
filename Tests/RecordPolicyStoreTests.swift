import XCTest
@testable import GymNote

@MainActor
final class RecordPolicyStoreTests: XCTestCase {
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

    private func legacyData() -> AppData {
        let exercise = Exercise(name: "푸쉬업", sets: 1, detail: "20회")
        var session = WorkoutSession(startedAt: Date(), plan: DayPlan(title: "운동", exercises: [exercise]))
        session.completedSets[exercise.id.uuidString] = 1
        session.actualReps[exercise.id.uuidString] = [20]
        var data = AppData.empty
        data.workouts = [session]
        return data
    }

    func testNearLimitStoredCacheRemainsReadableWithoutOverwritingOriginal() throws {
        var snapshot = StoredWorkout(data: legacyData())
        snapshot.data.scheduledPlans["2099-01-01"] = DayPlan(title: "", exercises: [])
        let count = try JSONEncoder().encode(snapshot).count
        snapshot.data.scheduledPlans["2099-01-01"]!.title = String(repeating: "x", count: 1_999_950 - count)
        let raw = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(raw.count, 1_999_950)
        let file = folder.appendingPathComponent("gymnote-data.json")
        try raw.write(to: file)
        let restored = try SharedStore.snapshot(userID: nil)
        XCTAssertEqual(restored.data.exerciseRecords()[AppData.exerciseKey("푸쉬업")]?.bestSet?.value, 20)
        XCTAssertEqual(try Data(contentsOf: file), raw)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("backup-guest-record-policy.json").path))
    }

    func testNearLimitPureGuestMigrationRemainsReadableAndBackedUp() throws {
        var data = legacyData()
        data.scheduledPlans["2099-01-01"] = DayPlan(title: "", exercises: [])
        let count = try JSONEncoder().encode(data).count
        data.scheduledPlans["2099-01-01"]!.title = String(repeating: "x", count: 1_999_950 - count)
        let raw = try JSONEncoder().encode(data)
        let file = folder.appendingPathComponent("gymnote-data.json")
        try raw.write(to: file)
        let restored = try SharedStore.snapshot(userID: nil)
        XCTAssertEqual(restored.data.exerciseRecords()[AppData.exerciseKey("푸쉬업")]?.bestSet?.value, 20)
        XCTAssertEqual(try Data(contentsOf: file), raw)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("guest-before-accounts.json").path))
    }

    func testLaterLegacyCloudJournalCannotReplaceRetainedBest() throws {
        let selection = try SharedStore.activate(userID: UUID())
        var first = legacyData()
        first.preserveExistingBestRecords()
        var stored = try SharedStore.snapshot(userID: selection.userID)
        try SharedStore.replaceWithCloud(first, version: 1, revision: stored.revision, selection: selection)
        stored = try SharedStore.snapshot(userID: selection.userID)
        var legacy = first
        legacy.recordWorkouts = nil
        let exerciseID = legacy.workouts[0].plan.exercises[0].id.uuidString
        legacy.workouts[0].actualReps[exerciseID] = [100]
        try SharedStore.replaceWithCloud(legacy, version: 2, revision: stored.revision, selection: selection)
        let restored = try SharedStore.snapshot(userID: selection.userID)
        XCTAssertEqual(restored.data.workouts[0].actualReps[exerciseID], [100])
        XCTAssertEqual(restored.data.exerciseRecords()[AppData.exerciseKey("푸쉬업")]?.bestSet?.value, 20)
        XCTAssertTrue(restored.dirty)
    }
}
