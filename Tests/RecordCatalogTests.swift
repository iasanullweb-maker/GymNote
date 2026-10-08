import XCTest
@testable import GymNote

@MainActor
final class RecordCatalogTests: XCTestCase {
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

    func testLegacyRecordsNeverBecomeCommonRecords() {
        let legacy = RecordEntry(typeID: "pushup", date: Date(), value: 30)
        let data = AppData(week: [], records: [legacy])
        let common = CatalogRecordType.defaults[0].recordType
        XCTAssertNil(data.best(common))
        XCTAssertEqual(data.best(RecordType.defaults[0])?.id, legacy.id)
        XCTAssertEqual(data.recordDisplayTypes(catalog: CatalogRecordType.defaults).count, 6)
    }

    func testEmptyCatalogRemainsEmptyAndDoesNotRestoreDefaults() throws {
        try SharedStore.saveRecordCatalog(RecordCatalogCache(project: "test", types: [], fetchedAt: Date()))
        XCTAssertEqual(SharedStore.recordCatalog()?.types, [])
        XCTAssertTrue(SharedStore.widgetSnapshot().0.recordTypes.isEmpty)
    }

    func testWidgetCatalogProjectionDoesNotRewriteLegacyBackup() throws {
        _ = try SharedStore.activate(userID: nil)
        let original = try SharedStore.snapshot(userID: nil).data
        var types = CatalogRecordType.defaults
        types[0].active = false
        types[2].position = 0
        try SharedStore.saveRecordCatalog(RecordCatalogCache(project: "test", types: types, fetchedAt: Date()))
        XCTAssertEqual(SharedStore.widgetSnapshot().0.recordTypes.map(\.id), [types[2].id, types[1].id])
        XCTAssertEqual(try SharedStore.snapshot(userID: nil).data, original)
    }

    func testNewRecordsRequireActiveCommonDefinition() {
        let model = AppModel(previewData: .empty)
        let legacy = RecordEntry(typeID: "custom", date: Date(), value: 5)
        XCTAssertFalse(model.addRecord(legacy))
        XCTAssertTrue(model.data.records.isEmpty)
        let common = RecordEntry(typeID: CatalogRecordType.defaults[0].id, date: Date(), value: 5)
        XCTAssertTrue(model.addRecord(common))
        XCTAssertEqual(model.data.records, [common])
        XCTAssertNotNil(model.data.recordType(common.typeID))
        XCTAssertFalse(model.addRecord(RecordEntry(typeID: common.typeID, date: Date(), value: .infinity)))
        XCTAssertEqual(model.data.records.count, 1)
    }
}
