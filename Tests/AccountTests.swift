import XCTest
@testable import GymNote

final class AuthStub: URLProtocol {
    static var reply: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.reply!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
final class AccountTests: XCTestCase {
    private var folder: URL!
    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        SharedStore.testingDirectory = folder
    }
    override func tearDown() async throws {
        SharedStore.testingDirectory = nil
        AuthStub.reply = nil
        try FileManager.default.removeItem(at: folder)
    }

    func testDailyPersistenceImportAndAccountIsolation() throws {
        let accountID = UUID()
        let selected = try SharedStore.activate(userID: accountID)
        let base = try SharedStore.snapshot(userID: accountID).data
        var edited = base
        let item = DailyItem(title: "독서", kind: .habit)
        edited.saveDailyItem(item)
        edited.toggleDailyCompletion(item.id, on: Date())
        _ = try SharedStore.persistEdits(from: base, to: edited, selection: selected)
        let loaded = try SharedStore.snapshot(userID: accountID).data
        XCTAssertEqual(loaded.dailyItems, edited.dailyItems)
        XCTAssertEqual(loaded.dailyCompletions, edited.dailyCompletions)
        _ = try SharedStore.activate(userID: UUID())
        XCTAssertTrue(SharedStore.load().dailyItems.isEmpty)
        XCTAssertThrowsError(try SharedStore.persistEdits(from: base, to: edited, selection: selected))
        let guest = try SharedStore.activate(userID: nil)
        let guestBase = try SharedStore.snapshot(userID: nil).data
        var guestEdited = guestBase
        guestEdited.saveDailyItem(DailyItem(title: "정리"))
        _ = try SharedStore.persistEdits(from: guestBase, to: guestEdited, selection: guest)
        let active = try SharedStore.activate(userID: accountID)
        try SharedStore.importGuest(selection: active)
        let imported = try SharedStore.snapshot(userID: accountID).data
        XCTAssertEqual(imported.dailyItems.count, 2)
        XCTAssertEqual(imported.dailyCompletions, edited.dailyCompletions)
    }

    func testDailyPreviewEditsNeverWriteToStore() throws {
        let before = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        let preview = AppModel(previewData: .empty)
        let item = DailyItem(title: "미리보기")
        preview.data.saveDailyItem(item)
        preview.data.toggleDailyCompletion(item.id, on: Date())
        XCTAssertEqual(preview.data.dailyCompletions.count, 1)
        XCTAssertNil(preview.storageError)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), before)
    }

    func testGuestMigrationAndAccountIsolation() throws {
        var legacy = AppData.sample
        legacy.records = [RecordEntry(typeID: "pushup", date: Date(), value: 42)]
        try JSONEncoder().encode(legacy).write(to: folder.appendingPathComponent("gymnote-data.json"))
        let guest = try SharedStore.activate(userID: nil)
        XCTAssertEqual(try SharedStore.snapshot(userID: nil).data, legacy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("guest-before-accounts.json").path))
        let a = UUID(), b = UUID()
        let activeA = try SharedStore.activate(userID: a)
        XCTAssertTrue(try SharedStore.snapshot(userID: a).data.records.isEmpty)
        XCTAssertFalse(try SharedStore.snapshot(userID: a).dirty)
        try SharedStore.importGuest(selection: activeA)
        XCTAssertEqual(try SharedStore.snapshot(userID: a).data.records, legacy.records)
        _ = try SharedStore.activate(userID: b)
        XCTAssertTrue(SharedStore.load().records.isEmpty)
        XCTAssertThrowsError(try SharedStore.persistEdits(from: .empty, to: legacy, selection: activeA))
        _ = try SharedStore.activate(userID: nil)
        XCTAssertEqual(SharedStore.load().records, legacy.records)
        XCTAssertNotEqual(try SharedStore.selection(), guest)
    }

    func testStaleWidgetAndSyncAcknowledgement() throws {
        let a = UUID()
        let selection = try SharedStore.activate(userID: a)
        var data = AppData.sample
        let exercise = data.plan().exercises.first ?? Exercise(name: "운동", sets: 5, detail: "10", restSeconds: 0)
        data.scheduledPlans[DayKey.key()] = DayPlan(title: "테스트", exercises: [exercise])
        XCTAssertTrue(data.startWorkout())
        _ = try SharedStore.persistEdits(from: .empty, to: data, selection: selection)
        let uploaded = try SharedStore.snapshot(userID: a)
        try SharedStore.completeSet(exercise.id, generation: selection.generation.uuidString)
        try SharedStore.acknowledge(version: 1, revision: uploaded.revision, selection: selection)
        let after = try SharedStore.snapshot(userID: a)
        XCTAssertTrue(after.dirty, "업로드 도중 변경한 세트는 동기화 대기로 유지")
        XCTAssertEqual(after.serverVersion, 1)
        XCTAssertEqual(after.data.doneSets(exercise), 1)
        XCTAssertEqual(after.data.activeWorkout?.done, 1)
        XCTAssertThrowsError(try SharedStore.replaceWithCloud(.empty, version: 2, revision: uploaded.revision, selection: selection))
        let next = try SharedStore.activate(userID: UUID())
        try SharedStore.completeSet(exercise.id, generation: selection.generation.uuidString)
        XCTAssertEqual(try SharedStore.snapshot(userID: next.userID).data, .empty)
    }

    func testCorruptAccountIsNeverOverwritten() throws {
        let a = UUID()
        _ = try SharedStore.activate(userID: a)
        let file = folder.appendingPathComponent("account-\(a.uuidString.lowercased()).json")
        let broken = Data("broken".utf8)
        try broken.write(to: file)
        XCTAssertThrowsError(try SharedStore.snapshot(userID: a))
        XCTAssertEqual(try Data(contentsOf: file), broken)
    }

    func testCorruptGuestStillHidesAccount() throws {
        let account = try SharedStore.activate(userID: UUID())
        let file = folder.appendingPathComponent("gymnote-data.json")
        try Data("broken".utf8).write(to: file)
        _ = try SharedStore.activate(userID: nil)
        XCTAssertNil(try SharedStore.selection().userID)
        XCTAssertEqual(SharedStore.widgetSnapshot().0, .empty)
        XCTAssertThrowsError(try SharedStore.snapshot(userID: nil))
        XCTAssertThrowsError(try SharedStore.persistEdits(from: .empty, to: .sample, selection: account))
        XCTAssertEqual(try Data(contentsOf: file), Data("broken".utf8))
    }

    func testInvalidGuestEnvelopeCannotBecomeSampleData() throws {
        _ = try SharedStore.activate(userID: nil)
        let snapshot = try SharedStore.snapshot(userID: nil)
        var fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
        fields["revision"] = "invalid-revision"
        let corrupted = try JSONSerialization.data(withJSONObject: fields)
        let file = folder.appendingPathComponent("gymnote-data.json")
        try corrupted.write(to: file)
        XCTAssertThrowsError(try SharedStore.snapshot(userID: nil))
        XCTAssertEqual(try Data(contentsOf: file), corrupted)
        try Data("{}".utf8).write(to: file)
        XCTAssertThrowsError(try SharedStore.snapshot(userID: nil))
        XCTAssertEqual(try Data(contentsOf: file), Data("{}".utf8))
    }

    func testHTTPAuthenticationAndErrorHandling() async throws {
        let config = AuthConfiguration(url: URL(string: "https://test.supabase.co")!, publicKey: "sb_publishable_test")
        let settings = URLSessionConfiguration.ephemeral
        settings.protocolClasses = [AuthStub.self]
        let client = AuthClient(config: config, configuration: settings)
        AuthStub.reply = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "sb_publishable_test")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(request.url?.path, "/rest/v1/rpc/load_workout")
            return (200, Data("[]".utf8))
        }
        let downloaded = try await client.download(token: "test-token")
        XCTAssertNil(downloaded)
        AuthStub.reply = { _ in (422, Data("{\"error_code\":\"otp_expired\"}".utf8)) }
        do {
            _ = try await client.verify(email: "test@example.com", code: "123456")
            XCTFail("인증 실패가 성공으로 처리되면 안 됨")
        } catch AccountError.unauthorized {} catch { XCTFail("Unexpected error: \(error)") }
        AuthStub.reply = { _ in (200, Data("[]".utf8)) }
        do {
            _ = try await client.upload(StoredWorkout(data: .empty), token: "test-token")
            XCTFail("CAS 충돌은 명시적으로 처리")
        } catch AccountError.conflict {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testKeychainNeverUsesSharedJSONAndClears() throws {
        let vault = SessionVault(project: "test-\(UUID())")
        defer { try? vault.clear() }
        let session = AccountSession(accessToken: "unique-access-token", refreshToken: "unique-refresh-token",
                                     expiresAt: Date().timeIntervalSince1970 + 3600,
                                     user: AccountUser(id: UUID(), email: "test@example.com"))
        try vault.write(session)
        XCTAssertEqual(try vault.read()?.refreshToken, session.refreshToken)
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            let text = String(decoding: try Data(contentsOf: file), as: UTF8.self)
            XCTAssertFalse(text.contains(session.accessToken) || text.contains(session.refreshToken))
        }
        try vault.clear()
        XCTAssertNil(try vault.read())
    }

    func testLoginRefreshAndLogoutKeepGuestSeparate() async throws {
        let project = "test-\(UUID().uuidString.lowercased()).supabase.co"
        let vault = SessionVault(project: project)
        defer { try? vault.clear() }
        let userID = UUID()
        let settings = URLSessionConfiguration.ephemeral
        settings.protocolClasses = [AuthStub.self]
        let client = AuthClient(config: AuthConfiguration(url: URL(string: "https://\(project)")!, publicKey: "sb_publishable_test"), configuration: settings)
        var refreshed = false
        var revoked = false
        AuthStub.reply = { request in
            switch request.url!.path {
            case "/auth/v1/otp": return (200, Data("{}".utf8))
            case "/auth/v1/verify":
                return (200, try JSONSerialization.data(withJSONObject: [
                    "access_token": "first-access", "refresh_token": "first-refresh", "expires_in": 0, "expires_at": 0,
                    "user": ["id": userID.uuidString, "email": "test@example.com"],
                ]))
            case "/auth/v1/user":
                return (200, try JSONEncoder().encode(AccountUser(id: userID, email: "test@example.com")))
            case "/auth/v1/token":
                refreshed = true
                return (200, try JSONSerialization.data(withJSONObject: [
                    "access_token": "rotated-access", "refresh_token": "rotated-refresh", "expires_in": 3600,
                    "user": ["id": userID.uuidString, "email": "test@example.com"],
                ]))
            case "/auth/v1/logout":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer rotated-access")
                revoked = true
                return (204, Data())
            default: throw URLError(.notConnectedToInternet)
            }
        }
        let model = AppModel()
        let entry = RecordEntry(typeID: "pushup", date: Date(), value: 42)
        model.data.records = [entry]
        let account = AccountModel(model: model, client: client)
        await account.bootstrap()
        await account.sendCode(email: "test@example.com", createUser: true, consent: true)
        await account.verify(code: "123456")
        XCTAssertEqual(account.user?.id, userID)
        XCTAssertEqual(model.selection.userID, userID)
        XCTAssertTrue(model.data.records.isEmpty, "로그인만으로 게스트 기록을 가져오지 않음")
        XCTAssertEqual(try vault.read()?.refreshToken, "first-refresh")
        await account.signOut()
        XCTAssertTrue(refreshed && revoked)
        XCTAssertNil(account.user)
        XCTAssertNil(try vault.read())
        XCTAssertNil(model.selection.userID)
        XCTAssertEqual(model.data.records, [entry])
    }
}
