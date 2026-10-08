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
    static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }
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
        let account = AccountModel(model: model, client: client, initialConnection: .online, monitorConnectivity: false)
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

    private func stubClient() -> AuthClient {
        let settings = URLSessionConfiguration.ephemeral
        settings.protocolClasses = [AuthStub.self]
        return AuthClient(config: AuthConfiguration(url: URL(string: "https://test-\(UUID().uuidString.lowercased()).supabase.co")!,
                                                    publicKey: "sb_publishable_test"), configuration: settings)
    }

    func testOfflineGuestStartsWithLocalRecordsAndOnlineShowsLogin() async throws {
        let model = AppModel()
        let record = RecordEntry(typeID: "pushup", date: Date(), value: 17)
        model.data.records = [record]
        let account = AccountModel(model: model, client: stubClient(), initialConnection: .offline, monitorConnectivity: false)
        AuthStub.reply = { _ in XCTFail("오프라인에서는 인증 요청을 보내지 않음"); throw URLError(.notConnectedToInternet) }
        await account.bootstrap()
        XCTAssertTrue(account.initialized)
        XCTAssertFalse(account.showsWelcome)
        XCTAssertEqual(model.data.records, [record])
        await account.sendCode(email: "test@example.com", createUser: true, consent: true)
        XCTAssertNil(account.pendingEmail)
        account.updateConnection(.online)
        XCTAssertTrue(account.showsWelcome)
        account.continueAsGuest()
        XCTAssertFalse(account.showsWelcome)
        XCTAssertNil(model.selection.userID)
        XCTAssertEqual(model.data.records, [record])
    }

    func testOfflineAccountKeepsIdentityAndUploadsWhenWiFiReturns() async throws {
        let client = stubClient()
        let vault = SessionVault(project: client.config.url.host!)
        defer { try? vault.clear() }
        let id = UUID()
        let scope = try SharedStore.activate(userID: id)
        let original = RecordEntry(typeID: "pushup", date: Date(), value: 21)
        var data = AppData.empty
        data.records = [original]
        _ = try SharedStore.persistEdits(from: .empty, to: data, selection: scope)
        try vault.write(AccountSession(accessToken: "expired", refreshToken: "cached-refresh", expiresAt: 0,
                                       user: AccountUser(id: id, email: "test@example.com")))
        let model = AppModel()
        let guestRecord = RecordEntry(typeID: "pushup", date: Date(), value: 99)
        model.data.records = [guestRecord]
        let account = AccountModel(model: model, client: client, initialConnection: .offline, monitorConnectivity: false)
        var requestCount = 0
        AuthStub.reply = { request in
            requestCount += 1
            switch request.url!.path {
            case "/auth/v1/token":
                return (200, try JSONSerialization.data(withJSONObject: ["access_token": "fresh", "refresh_token": "rotated", "expires_in": 3600,
                    "user": ["id": id.uuidString, "email": "test@example.com"]]))
            case "/rest/v1/rpc/load_workout": return (200, Data("[]".utf8))
            case "/rest/v1/rpc/save_workout":
                let body = try JSONSerialization.jsonObject(with: AuthStub.body(of: request)) as! [String: Any]
                let payload = body["p_payload"] as! [String: Any]
                XCTAssertEqual((payload["records"] as! [Any]).count, 2)
                return (200, try JSONSerialization.data(withJSONObject: [["version": 1, "payload": payload]]))
            default: throw URLError(.badURL)
            }
        }
        await account.bootstrap()
        XCTAssertEqual(requestCount, 0, "만료된 세션도 오프라인에서 서버 검증을 시도하지 않음")
        XCTAssertEqual(account.user?.id, id)
        XCTAssertEqual(model.selection.userID, id)
        XCTAssertEqual(model.data.records, [original])
        XCTAssertFalse(account.showsWelcome)
        let offlineRecord = RecordEntry(typeID: "pushup", date: Date(), value: 30)
        model.data.records.append(offlineRecord)
        await account.synchronize()
        XCTAssertEqual(requestCount, 0)
        XCTAssertTrue(try SharedStore.snapshot(userID: id).dirty)
        account.updateConnection(.online)
        await account.synchronize()
        XCTAssertEqual(requestCount, 3)
        XCTAssertFalse(try SharedStore.snapshot(userID: id).dirty)
        XCTAssertEqual(model.data.records, [original, offlineRecord])
        XCTAssertEqual(try SharedStore.snapshot(userID: nil).data.records, [guestRecord], "게스트 기록과 계정 기록을 섞지 않음")
    }

    func testConsentedGuestImportRetriesAfterReconnection() async throws {
        let client = stubClient()
        let vault = SessionVault(project: client.config.url.host!)
        defer { try? vault.clear() }
        let id = UUID()
        let model = AppModel()
        let record = RecordEntry(typeID: "pushup", date: Date(), value: 42)
        model.data.records = [record]
        let account = AccountModel(model: model, client: client, initialConnection: .online, monitorConnectivity: false)
        var serverAvailable = false
        var uploadedRecords = 0
        AuthStub.reply = { request in
            switch request.url!.path {
            case "/auth/v1/otp": return (200, Data("{}".utf8))
            case "/auth/v1/verify":
                return (200, try JSONSerialization.data(withJSONObject: ["access_token": "verified", "refresh_token": "refresh", "expires_in": 3600,
                    "user": ["id": id.uuidString, "email": "test@example.com"]]))
            case "/auth/v1/user": return (200, try JSONEncoder().encode(AccountUser(id: id, email: "test@example.com")))
            case "/rest/v1/rpc/load_workout":
                guard serverAvailable else { throw URLError(.notConnectedToInternet) }
                return (200, Data("[]".utf8))
            case "/rest/v1/rpc/save_workout":
                let body = try JSONSerialization.jsonObject(with: AuthStub.body(of: request)) as! [String: Any]
                let payload = body["p_payload"] as! [String: Any]
                uploadedRecords = (payload["records"] as! [Any]).count
                return (200, try JSONSerialization.data(withJSONObject: [["version": 1, "payload": payload]]))
            default: throw URLError(.badURL)
            }
        }
        await account.bootstrap()
        await account.sendCode(email: "test@example.com", createUser: true, consent: true)
        await account.verify(code: "123456", importDeviceRecords: true)
        await account.synchronize()
        XCTAssertEqual(model.data.records, [record], "첫 서버 읽기가 실패해도 동의한 기기 기록으로 계속 진행")
        account.updateConnection(.offline)
        let reopenedModel = AppModel()
        let reopenedAccount = AccountModel(model: reopenedModel, client: client, initialConnection: .offline, monitorConnectivity: false)
        await reopenedAccount.bootstrap()
        XCTAssertEqual(reopenedModel.data.records, [record], "앱 재실행 후에도 가져온 기록 복원")
        serverAvailable = true
        reopenedAccount.updateConnection(.online)
        await reopenedAccount.synchronize()
        XCTAssertEqual(reopenedModel.data.records, [record])
        XCTAssertTrue(try SharedStore.snapshot(userID: id).importedGuest)
        XCTAssertEqual(uploadedRecords, 1)
        XCTAssertFalse(try SharedStore.snapshot(userID: id).dirty)
        XCTAssertEqual(try SharedStore.snapshot(userID: nil).data.records, [record])
    }

    func testInitialGuestImportAddsToExistingCloudBeforeUpload() async throws {
        let client = stubClient()
        let vault = SessionVault(project: client.config.url.host!)
        defer { try? vault.clear() }
        let id = UUID()
        let model = AppModel()
        let guest = RecordEntry(typeID: "pushup", date: Date(), value: 15)
        let serverRecord = RecordEntry(typeID: "pushup", date: Date(), value: 50)
        model.data.records = [guest]
        var cloud = AppData.empty
        cloud.records = [serverRecord]
        var uploaded = false
        AuthStub.reply = { request in
            switch request.url!.path {
            case "/auth/v1/otp": return (200, Data("{}".utf8))
            case "/auth/v1/verify":
                return (200, try JSONSerialization.data(withJSONObject: ["access_token": "verified", "refresh_token": "refresh", "expires_in": 3600,
                    "user": ["id": id.uuidString, "email": "test@example.com"]]))
            case "/auth/v1/user": return (200, try JSONEncoder().encode(AccountUser(id: id, email: "test@example.com")))
            case "/rest/v1/rpc/load_workout": return (200, try JSONEncoder().encode([CloudWorkout(version: 3, payload: cloud)]))
            case "/rest/v1/rpc/save_workout":
                let body = try JSONSerialization.jsonObject(with: AuthStub.body(of: request)) as! [String: Any]
                XCTAssertEqual(body["p_expected_version"] as? Int, 3)
                let payload = body["p_payload"] as! [String: Any]
                XCTAssertEqual((payload["records"] as! [Any]).count, 2)
                uploaded = true
                return (200, try JSONSerialization.data(withJSONObject: [["version": 4, "payload": payload]]))
            default: throw URLError(.badURL)
            }
        }
        let account = AccountModel(model: model, client: client, initialConnection: .online, monitorConnectivity: false)
        await account.bootstrap()
        await account.sendCode(email: "test@example.com", createUser: true, consent: true)
        await account.verify(code: "123456", importDeviceRecords: true)
        await account.synchronize()
        XCTAssertTrue(uploaded)
        XCTAssertNil(account.conflict)
        XCTAssertEqual(Set(model.data.records.map(\.id)), Set([guest.id, serverRecord.id]))
        XCTAssertEqual(try SharedStore.snapshot(userID: id).serverVersion, 4)
        XCTAssertFalse(try SharedStore.snapshot(userID: id).dirty)
        let backups = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("backup-\(id.uuidString.lowercased())-") }
        XCTAssertEqual(backups.count, 2)
    }
}
