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
        AuthStub.reply = nil
        SharedStore.testingDirectory = nil
        try FileManager.default.removeItem(at: folder)
    }

    private func catalogClient() -> AuthClient {
        let settings = URLSessionConfiguration.ephemeral
        settings.protocolClasses = [AuthStub.self]
        return AuthClient(config: AuthConfiguration(url: URL(string: "https://catalog-\(UUID().uuidString.lowercased()).supabase.co")!,
                                                    publicKey: "sb_publishable_test"), configuration: settings)
    }

    func testCatalogWorkoutCopiesPreservePlansAndPrivateLibrary() throws {
        var type = CatalogRecordType.defaults[0]
        type.name = "관리자 운동"
        let first = type.makeExercise()
        let second = type.makeExercise()
        XCTAssertNotEqual(first.id, second.id, "각 루틴 슬롯은 독립된 진행 상태를 가져야 함")
        var data = AppData(week: [DayPlan(title: "공통 운동", exercises: [first])])
        data.exerciseLibrary = [Exercise(name: "개인 운동", sets: 5, detail: "8회")]
        let before = data
        type.name = "이름 수정"
        type.active = false
        _ = type.makeExercise()
        XCTAssertEqual(data, before, "공통 수정·중단은 기존 계획과 개인 목록을 덮어쓰지 않음")
        let restored = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(restored.week[0].exercises[0], first)
        XCTAssertEqual(restored.exerciseLibrary, data.exerciseLibrary)
    }

    func testCommonExercisesImportIntoManualWorkoutWithTimeAndWeight() throws {
        var timed = CatalogRecordType.defaults[0]
        timed.name = "플랭크"; timed.unit = "초"
        var draft = ManualWorkoutDraft()
        draft.append(timed.makeExercise())
        XCTAssertTrue(draft.moves[0].sets.allSatisfy { $0.reps.isEmpty })
        XCTAssertTrue(draft.isValid, "시간 운동에 반복 횟수를 만들어 넣지 않음")
        var weighted = timed
        weighted.name = "벤치 프레스"; weighted.unit = "kg"
        draft.append(weighted.makeExercise())
        XCTAssertFalse(draft.isValid, "무게 종목을 반복 횟수로 잘못 간주하지 않음")
        draft.moves[1].detail = "8회"
        for index in draft.moves[1].sets.indices {
            draft.moves[1].sets[index].reps = "8"
            draft.moves[1].sets[index].weight = "40"
        }
        let session = try XCTUnwrap(draft.session())
        XCTAssertEqual(session.plan.exercises.map(\.name), ["플랭크", "벤치 프레스"])
        XCTAssertEqual(session.actualWeights[session.plan.exercises[1].id.uuidString], [40, 40, 40])
    }

    func testGuestSeesNewAdministratorTypeAfterRefresh() async throws {
        var remote = CatalogRecordType.defaults
        let client = catalogClient()
        AuthStub.reply = { request in
            XCTAssertEqual(request.url?.path, "/rest/v1/rpc/list_record_catalog")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (200, try JSONEncoder().encode(remote))
        }
        let model = AppModel(previewData: .empty)
        let account = AccountModel(model: model, client: client, initialConnection: .online, monitorConnectivity: false)
        await account.refreshRecordCatalog()
        var added = remote[0]
        added.id = "common-new-v1"; added.name = "새 공통 운동"; added.position = 3
        remote.append(added)
        await account.refreshRecordCatalog()
        XCTAssertEqual(account.catalogTypes.last, added)
        XCTAssertEqual(SharedStore.recordCatalog()?.types.last, added)
        XCTAssertNotNil(account.catalogFetchedAt)
        XCTAssertNil(account.catalogMessage)
    }

    func testFreshCatalogStillDisplaysWhenCacheWriteFails() async throws {
        // A directory in place of the cache file makes the real atomic write fail.
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("record-catalog.json"),
                                                withIntermediateDirectories: false)
        var added = CatalogRecordType.defaults[0]
        added.id = "common-fresh-v1"; added.name = "최신 운동"
        AuthStub.reply = { _ in (200, try JSONEncoder().encode([added])) }
        let model = AppModel(previewData: .empty)
        let account = AccountModel(model: model, client: catalogClient(),
                                   initialConnection: .online, monitorConnectivity: false)
        await account.refreshRecordCatalog()
        XCTAssertEqual(account.catalogTypes, [added])
        XCTAssertNotNil(account.catalogFetchedAt)
        XCTAssertNotNil(account.catalogMessage)
    }

    func testCatalogNetworkFailurePreservesLastGoodList() async throws {
        let model = AppModel(previewData: .empty)
        let account = AccountModel(model: model, client: catalogClient(),
                                   initialConnection: .online, monitorConnectivity: false)
        AuthStub.reply = { _ in (200, try JSONEncoder().encode([] as [CatalogRecordType])) }
        await account.refreshRecordCatalog()
        AuthStub.reply = { _ in (500, Data()) }
        await account.refreshRecordCatalog()
        XCTAssertTrue(account.catalogTypes.isEmpty, "실패 때문에 서버가 비운 목록을 기본 목록으로 되돌리지 않음")
        XCTAssertNotNil(account.catalogMessage)
    }

    func testCancelledRefreshPreservesCatalogWithoutShowingAnError() async throws {
        let model = AppModel(previewData: .empty)
        let account = AccountModel(model: model, client: catalogClient(),
                                   initialConnection: .online, monitorConnectivity: false)
        let cancellations: [Error] = [CancellationError(), URLError(.cancelled),
            CancellationError() as NSError,
            NSError(domain: NSURLErrorDomain, code: URLError.cancelled.rawValue),
            NSError(domain: "TransportWrapper", code: 1,
                    userInfo: [NSUnderlyingErrorKey: URLError(.cancelled) as NSError])]
        for error in cancellations {
            // Each variant starts from success so one failure cannot poison later assertions.
            AuthStub.reply = { _ in (200, try JSONEncoder().encode([] as [CatalogRecordType])) }
            await account.refreshRecordCatalog()
            let fetchedAt = account.catalogFetchedAt
            AuthStub.reply = { _ in throw error }
            await account.refreshRecordCatalog()
            XCTAssertTrue(account.catalogTypes.isEmpty)
            XCTAssertEqual(account.catalogFetchedAt, fetchedAt)
            XCTAssertNil(account.catalogMessage, "취소 형식: \((error as NSError).domain)")
            XCTAssertFalse(account.catalogLoading)
        }
    }

    func testAlreadyCancelledTaskDoesNotRequestOrChangeCatalog() async throws {
        let model = AppModel(previewData: .empty)
        let account = AccountModel(model: model, client: catalogClient(),
                                   initialConnection: .online, monitorConnectivity: false)
        AuthStub.reply = { _ in XCTFail("취소된 갱신은 요청하지 않음"); return (500, Data()) }
        let refresh = Task { await account.refreshRecordCatalog() }
        refresh.cancel()
        await refresh.value
        XCTAssertEqual(account.catalogTypes, CatalogRecordType.defaults)
        XCTAssertNil(account.catalogMessage)
        XCTAssertNil(account.catalogFetchedAt)
        XCTAssertFalse(account.catalogLoading)
    }

    func testAdministratorRefreshKeepsScreenVisibleWithoutBlockingAccountActions() async throws {
        let client = catalogClient()
        let vault = SessionVault(project: client.config.url.host!)
        defer { try? vault.clear() }
        let identity = AccountUser(id: UUID(), email: "admin@example.com")
        try vault.write(AccountSession(accessToken: "admin-token", refreshToken: "refresh",
                                       expiresAt: Date().timeIntervalSince1970 + 3600, user: identity))
        let model = AppModel()
        let account = AccountModel(model: model, client: client, initialConnection: .online,
                                   monitorConnectivity: false)
        await account.bootstrap()
        AuthStub.reply = { request in
            if request.url?.path == "/rest/v1/rpc/is_record_catalog_admin" { return (200, Data("true".utf8)) }
            return (200, try JSONEncoder().encode(CatalogRecordType.defaults))
        }
        await account.refreshRecordCatalog()
        XCTAssertTrue(account.canManageCatalog)

        let checking = expectation(description: "Background administrator check started")
        let releaseResponse = DispatchSemaphore(value: 0)
        AuthStub.reply = { request in
            if request.url?.path == "/rest/v1/rpc/is_record_catalog_admin" {
                checking.fulfill()
                guard releaseResponse.wait(timeout: .now() + 5) == .success else { throw URLError(.timedOut) }
                return (200, Data("false".utf8))
            }
            return (200, try JSONEncoder().encode(CatalogRecordType.defaults))
        }
        let refresh = Task { await account.refreshRecordCatalog() }
        await fulfillment(of: [checking], timeout: 2)
        XCTAssertTrue(account.canManageCatalog, "확인 중에는 기존 관리자 화면 유지")
        XCTAssertFalse(account.busy, "주기적인 확인이 다른 계정 작업을 막지 않음")
        releaseResponse.signal()
        await refresh.value
        XCTAssertFalse(account.canManageCatalog, "서버가 권한 없음을 확인한 뒤 반영")
        XCTAssertFalse(account.busy)
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
        XCTAssertFalse(model.addRecord(RecordEntry(typeID: common.typeID, date: Date(), value: 5.004)))
        XCTAssertFalse(model.addRecord(RecordEntry(typeID: CatalogRecordType.defaults[2].id, date: Date(), value: 12.9)))
        XCTAssertEqual(model.data.records.count, 1)
    }
}
