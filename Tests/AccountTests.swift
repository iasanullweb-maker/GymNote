import AuthenticationServices
import XCTest
@testable import GymNote

final class AuthStub: URLProtocol {
    static var reply: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let reply = Self.reply else { throw URLError(.cannotConnectToHost) }
            let (status, data) = try reply(request)
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

    // MARK: - Google/Apple (Supabase OAuth + PKCE)

    func testPKCEMatchesRFC7636AndVerifiersAreUnique() throws {
        XCTAssertEqual(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let first = try PKCE.verifier(), second = try PKCE.verifier()
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.count, 43)
        XCTAssertTrue(first.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
    }

    func testAuthorizeURLUsesPKCEAndExactReturnAddress() throws {
        let client = stubClient()
        let attempt = try client.beginOAuth(.google)
        let parts = URLComponents(url: attempt.url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(parts.scheme, "https")
        XCTAssertEqual(parts.host, client.config.url.host)
        XCTAssertEqual(parts.path, "/auth/v1/authorize")
        let query = Dictionary(uniqueKeysWithValues: parts.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["provider"], "google")
        XCTAssertEqual(query["redirect_to"], "com.gymnote.app://auth-callback")
        XCTAssertEqual(query["code_challenge_method"], "s256")
        XCTAssertEqual(query["code_challenge"], PKCE.challenge(for: attempt.verifier))
        XCTAssertNil(query["code_verifier"], "검증용 비밀값은 브라우저로 보내지 않음")
        XCTAssertNotEqual(try client.beginOAuth(.google).verifier, attempt.verifier)
    }

    func testCallbackAcceptsOnlyOurReturnAddress() throws {
        XCTAssertEqual(try AuthClient.authorizationCode(from: URL(string: "com.gymnote.app://auth-callback?code=3f7c2a10-1b2c-4d5e-8f90-123456789abc")!),
                       "3f7c2a10-1b2c-4d5e-8f90-123456789abc")
        for bad in ["https://evil.example/auth-callback?code=abc", "com.other.app://auth-callback?code=abc",
                    "com.gymnote.app://other?code=abc", "com.gymnote.app://auth-callback/extra?code=abc",
                    "com.gymnote.app://auth-callback", "com.gymnote.app://auth-callback?code=a%20b",
                    "com.gymnote.app://auth-callback?error=server_error&error_description=x",
                    "com.gymnote.app://auth-callback#error=invalid_request&code=abc"] {
            XCTAssertThrowsError(try AuthClient.authorizationCode(from: URL(string: bad)!), bad)
        }
        XCTAssertThrowsError(try AuthClient.authorizationCode(from: URL(string: "com.gymnote.app://auth-callback?error=access_denied")!)) { error in
            guard case AccountError.cancelled = error else { return XCTFail("동의 거부는 취소로 처리: \(error)") }
        }
    }

    func testAccountUserProvidersSurviveKeychainRoundTrip() throws {
        let id = UUID()
        let fromServer = try JSONDecoder().decode(AccountUser.self, from: JSONSerialization.data(withJSONObject: [
            "id": id.uuidString, "email": "relay@privaterelay.appleid.com",
            "app_metadata": ["provider": "apple", "providers": ["apple", "google"]],
        ]))
        XCTAssertEqual(fromServer.providers, ["apple", "google"])
        let legacy = try JSONDecoder().decode(AccountUser.self, from: JSONSerialization.data(withJSONObject: ["id": id.uuidString]))
        XCTAssertEqual(legacy.providers, [])
        let vault = SessionVault(project: "test-\(UUID())")
        defer { try? vault.clear() }
        try vault.write(AccountSession(accessToken: "a", refreshToken: "r", expiresAt: 0, user: fromServer))
        XCTAssertEqual(try vault.read()?.user.providers, ["apple", "google"])
    }

    /// Records the PKCE challenge the browser saw and checks the exchange proves the same verifier.
    private func socialStub(id: UUID, providers: [String: Bool] = ["google": true, "apple": false, "email": true],
                            userProviders: [String] = ["google"], email: String = "user@gmail.com",
                            challenge: @escaping () -> String?, onRequest: ((URLRequest) -> Void)? = nil) {
        AuthStub.reply = { request in
            onRequest?(request)
            switch request.url!.path {
            case "/auth/v1/settings":
                XCTAssertEqual(request.httpMethod, "GET")
                return (200, try JSONSerialization.data(withJSONObject: ["external": providers]))
            case "/auth/v1/token":
                XCTAssertEqual(request.url?.query, "grant_type=pkce")
                let body = try JSONSerialization.jsonObject(with: AuthStub.body(of: request)) as! [String: String]
                XCTAssertEqual(body["auth_code"], "auth-code-1")
                guard let verifier = body["code_verifier"], PKCE.challenge(for: verifier) == challenge() else { return (400, Data()) }
                return (200, try JSONSerialization.data(withJSONObject: [
                    "access_token": "social-access-\(UUID())", "refresh_token": "social-refresh", "expires_in": 3600,
                    "user": ["id": id.uuidString, "email": email, "app_metadata": ["providers": userProviders]]]))
            case "/auth/v1/user":
                return (200, try JSONEncoder().encode(AccountUser(id: id, email: email, providers: userProviders)))
            case "/auth/v1/logout": return (204, Data())
            case "/rest/v1/rpc/load_workout": return (200, Data("[]".utf8))
            case "/rest/v1/rpc/save_workout":
                let body = try JSONSerialization.jsonObject(with: AuthStub.body(of: request)) as! [String: Any]
                return (200, try JSONSerialization.data(withJSONObject: [["version": 1, "payload": body["p_payload"]!]]))
            default: throw URLError(.badURL)
            }
        }
    }

    private func browser(returning code: String = "auth-code-1", seen: @escaping (URL) -> Void) -> (URL) async throws -> URL {
        { url in
            seen(url)
            return URL(string: "com.gymnote.app://auth-callback?code=\(code)")!
        }
    }

    private func challenge(of url: URL?) -> String? {
        url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "code_challenge" }?.value }
    }

    func testGoogleLoginStoresSessionWithoutImportingGuestRecords() async throws {
        let client = stubClient()
        let vault = SessionVault(project: client.config.url.host!)
        defer { try? vault.clear() }
        let id = UUID()
        let model = AppModel()
        let guest = RecordEntry(typeID: "pushup", date: Date(), value: 33)
        model.data.records = [guest]
        var opened: URL?
        socialStub(id: id, challenge: { self.challenge(of: opened) })
        let account = AccountModel(model: model, client: client, initialConnection: .online, monitorConnectivity: false)
        await account.bootstrap()
        await account.refreshProviders()
        XCTAssertTrue(account.canSignIn(with: .google))
        XCTAssertFalse(account.canSignIn(with: .apple), "서버에서 꺼진 Apple은 비활성")
        await account.signIn(with: .google, authenticate: browser { opened = $0 })
        XCTAssertNotNil(opened)
        XCTAssertEqual(account.user?.id, id)
        XCTAssertEqual(account.user?.providers, ["google"])
        XCTAssertEqual(model.selection.userID, id)
        XCTAssertTrue(model.data.records.isEmpty, "동의 없이 기기 기록을 가져오지 않음")
        XCTAssertEqual(try SharedStore.snapshot(userID: nil).data.records, [guest])
        XCTAssertEqual(try vault.read()?.user.id, id)
        XCTAssertFalse(account.busy)
    }

    func testGoogleLoginImportsGuestOnlyWithConsent() async throws {
        let client = stubClient()
        let vault = SessionVault(project: client.config.url.host!)
        defer { try? vault.clear() }
        let id = UUID()
        let model = AppModel()
        let guest = RecordEntry(typeID: "pushup", date: Date(), value: 44)
        model.data.records = [guest]
        var opened: URL?
        socialStub(id: id, challenge: { self.challenge(of: opened) })
        let account = AccountModel(model: model, client: client, initialConnection: .online, monitorConnectivity: false)
        await account.bootstrap()
        await account.refreshProviders()
        await account.signIn(with: .google, importDeviceRecords: true, authenticate: browser { opened = $0 })
        XCTAssertEqual(model.selection.userID, id)
        XCTAssertEqual(model.data.records, [guest])
        XCTAssertEqual(try SharedStore.snapshot(userID: nil).data.records, [guest], "게스트 원본 보존")
    }

    func testCancelledFailedAndDisabledSocialLoginKeepGuest() async throws {
        let client = stubClient()
        let vault = SessionVault(project: client.config.url.host!)
        defer { try? vault.clear() }
        let model = AppModel()
        var tokenRequests = 0
        socialStub(id: UUID(), challenge: { nil }) { if $0.url?.path == "/auth/v1/token" { tokenRequests += 1 } }
        let account = AccountModel(model: model, client: client, initialConnection: .online, monitorConnectivity: false)
        await account.bootstrap()
        await account.refreshProviders()
        // 사용자가 인증 창을 닫음
        await account.signIn(with: .google) { _ in throw ASWebAuthenticationSessionError(.canceledLogin) }
        XCTAssertNil(account.user)
        XCTAssertEqual(account.message, AccountError.cancelled.localizedDescription)
        // Google 동의 화면에서 거부
        await account.signIn(with: .google) { _ in URL(string: "com.gymnote.app://auth-callback?error=access_denied")! }
        XCTAssertEqual(account.message, AccountError.cancelled.localizedDescription)
        // 다른 주소로 돌아온 응답은 거부
        await account.signIn(with: .google) { _ in URL(string: "https://evil.example/auth-callback?code=auth-code-1")! }
        XCTAssertNil(account.user)
        // 다른 시도의 코드/검증값 불일치(challenge 없음)는 서버가 거부
        await account.signIn(with: .google, authenticate: browser { _ in })
        XCTAssertNil(account.user)
        XCTAssertEqual(tokenRequests, 1)
        // 서버에서 꺼진 방식은 인증 창을 열지 않음
        var openedApple = false
        await account.signIn(with: .apple) { url in openedApple = true; return url }
        XCTAssertFalse(openedApple)
        XCTAssertEqual(account.message, AccountError.providerUnavailable.localizedDescription)
        XCTAssertNil(model.selection.userID)
        XCTAssertNil(try vault.read())
        XCTAssertFalse(account.busy, "취소·실패 후 다시 시도 가능")
    }

    func testSocialButtonsStayDisabledOfflineAndWhenSettingsFail() async throws {
        let model = AppModel()
        let offline = AccountModel(model: model, client: stubClient(), initialConnection: .offline, monitorConnectivity: false)
        AuthStub.reply = { _ in XCTFail("오프라인에서는 설정을 묻지 않음"); throw URLError(.notConnectedToInternet) }
        await offline.bootstrap()
        await offline.refreshProviders()
        XCTAssertFalse(offline.canSignIn(with: .google))
        let failing = AccountModel(model: model, client: stubClient(), initialConnection: .online, monitorConnectivity: false)
        AuthStub.reply = { _ in (500, Data()) }
        await failing.bootstrap()
        await failing.refreshProviders()
        XCTAssertFalse(failing.canSignIn(with: .google))
        XCTAssertFalse(AccountModel(model: model, client: nil, initialConnection: .online, monitorConnectivity: false).canSignIn(with: .google))
    }

    func testSocialReauthenticationForDeletionRequiresSameAccount() async throws {
        let client = stubClient()
        let vault = SessionVault(project: client.config.url.host!)
        defer { try? vault.clear() }
        let id = UUID()
        try vault.write(AccountSession(accessToken: "old-access", refreshToken: "old-refresh",
                                       expiresAt: Date().timeIntervalSince1970 + 3600,
                                       user: AccountUser(id: id, email: "user@gmail.com", providers: ["google"])))
        let model = AppModel()
        var opened: URL?
        var revoked: [String] = []
        socialStub(id: UUID(), challenge: { self.challenge(of: opened) }) {
            if $0.url?.path == "/auth/v1/logout" { revoked.append($0.value(forHTTPHeaderField: "Authorization") ?? "") }
        }
        let account = AccountModel(model: model, client: client, initialConnection: .online, monitorConnectivity: false)
        await account.bootstrap()
        await account.refreshProviders()
        account.beginDeletion()
        XCTAssertFalse(account.canUseEmailForReauthentication, "Google 전용 계정은 이메일 인증번호로 확인하지 않음")
        XCTAssertTrue(account.canSignIn(with: .google))
        // 다른 Google 계정으로 인증하면 거부하고 새로 생긴 세션은 종료
        await account.signIn(with: .google, authenticate: browser { opened = $0 })
        XCTAssertFalse(account.readyToDelete)
        XCTAssertEqual(account.user?.id, id)
        XCTAssertEqual(model.selection.userID, id)
        XCTAssertEqual(account.message, AccountError.wrongAccount.localizedDescription)
        XCTAssertEqual(revoked.count, 1)
        XCTAssertEqual(try vault.read()?.accessToken, "old-access")
        // 같은 계정으로 다시 인증하면 삭제 가능, 이전 세션은 종료
        socialStub(id: id, challenge: { self.challenge(of: opened) }) {
            if $0.url?.path == "/auth/v1/logout" { revoked.append($0.value(forHTTPHeaderField: "Authorization") ?? "") }
        }
        await account.signIn(with: .google, authenticate: browser { opened = $0 })
        XCTAssertTrue(account.readyToDelete)
        XCTAssertEqual(revoked.last, "Bearer old-access")
        XCTAssertNotEqual(try vault.read()?.accessToken, "old-access")
        account.cancelDeletion()
        XCTAssertFalse(account.readyToDelete)
        XCTAssertFalse(account.isDeleting)
        XCTAssertFalse(account.isReauthenticating)
        XCTAssertNil(account.pendingEmail)
        XCTAssertNil(account.message)
    }

    func testDeletionScreenCloseExpiryAndResendState() async throws {
        let client = stubClient()
        let vault = SessionVault(project: client.config.url.host!)
        defer { try? vault.clear() }
        let id = UUID()
        try vault.write(AccountSession(accessToken: "old", refreshToken: "refresh",
                                       expiresAt: Date().timeIntervalSince1970 + 3600,
                                       user: AccountUser(id: id, email: "me@example.com", providers: ["google"])))
        let model = AppModel()
        var opened: URL?
        socialStub(id: id, challenge: { self.challenge(of: opened) })
        let account = AccountModel(model: model, client: client, initialConnection: .online, monitorConnectivity: false)
        await account.bootstrap()
        await account.refreshProviders()
        XCTAssertFalse(account.isDeleting, "일반 계정 진입은 삭제 절차가 아님")
        account.beginDeletion()
        XCTAssertTrue(account.isDeleting)
        account.closeAccountScreen()
        XCTAssertFalse(account.isDeleting, "창 닫기 후 삭제 상태 초기화")
        XCTAssertNil(account.message)
        account.beginDeletion()
        await account.signIn(with: .google) { url in
            XCTAssertTrue(account.blocksDismissal)
            XCTAssertEqual(account.operationTitle, "본인 확인 중…")
            account.cancelDeletion()
            account.closeAccountScreen()
            XCTAssertTrue(account.isDeleting, "처리 중 상태를 지우지 않음")
            return try await self.browser(seen: { opened = $0 })(url)
        }
        XCTAssertTrue(account.readyToDelete)
        XCTAssertFalse(account.deletionIsVerified(at: Date().addingTimeInterval(301)))
        account.expireDeletionVerification(at: Date().addingTimeInterval(301))
        XCTAssertFalse(account.readyToDelete)
        XCTAssertTrue(account.isDeleting, "만료 시 삭제 본인 확인 단계로 돌아감")
        XCTAssertEqual(account.messageContext, .authentication)
        XCTAssertEqual(account.message, "본인 확인이 만료됐어요. 다시 본인 확인을 해 주세요.")
        account.closeAccountScreen()
        XCTAssertFalse(account.isDeleting)
        account.updateConnection(.offline)
        account.beginDeletion()
        XCTAssertFalse(account.isDeleting, "오프라인에서는 삭제 절차를 시작하지 않음")
        account.updateConnection(.online)
        AuthStub.reply = { _ in (200, Data("{}".utf8)) }
        await account.sendCode(email: "me@example.com", createUser: false, consent: false)
        let sentAt = try XCTUnwrap(account.sentAt)
        XCTAssertEqual(account.resendSeconds(at: sentAt), 60)
        XCTAssertEqual(account.resendSeconds(at: sentAt.addingTimeInterval(59.2)), 1)
        XCTAssertEqual(account.resendSeconds(at: sentAt.addingTimeInterval(60)), 0)
        XCTAssertEqual(account.pendingEmail, "me@example.com")
        account.closeAccountScreen()
        XCTAssertNil(account.pendingEmail)
        XCTAssertNil(account.message)
        XCTAssertEqual(account.resendSeconds(at: sentAt), 60, "화면 전환으로 재발송 제한을 우회하지 않음")
        account.beginDeletion()
        XCTAssertEqual(account.resendSeconds(at: sentAt), 60, "삭제 절차 재진입에도 재발송 제한 유지")
        account.cancelDeletion()
        AuthStub.reply = { _ in (401, Data()) }
        await account.synchronize()
        XCTAssertTrue(account.needsLogin)
        XCTAssertFalse(account.isDeleting, "일반 재로그인이 삭제 절차를 시작하지 않음")
        XCTAssertEqual(account.messageContext, .backup)
        account.beginDeletion()
        XCTAssertFalse(account.isDeleting, "재로그인 필요 상태에서는 먼저 로그인")
        account.closeAccountScreen()
        XCTAssertTrue(account.needsLogin, "창 닫기로 만료된 로그인이 복구되지는 않음")
    }

    func testBackupFeedbackAndLastSyncAreAccountScoped() async throws {
        let client = stubClient()
        let vault = SessionVault(project: client.config.url.host!)
        let id = UUID()
        let key = "com.gymnote.lastSync.\(client.config.url.host!).\(id.uuidString)"
        defer { try? vault.clear(); UserDefaults.standard.removeObject(forKey: key) }
        try vault.write(AccountSession(accessToken: "access", refreshToken: "refresh",
                                       expiresAt: Date().timeIntervalSince1970 + 3600,
                                       user: AccountUser(id: id, email: "me@example.com")))
        let model = AppModel()
        socialStub(id: id, challenge: { nil })
        let account = AccountModel(model: model, client: client, initialConnection: .online, monitorConnectivity: false)
        await account.bootstrap()
        XCTAssertNil(account.lastSyncedAt)
        await account.synchronize()
        let synced = try XCTUnwrap(account.lastSyncedAt)
        XCTAssertEqual(account.messageContext, .backup)
        XCTAssertEqual(account.syncStatus, "동기화 완료")
        XCTAssertEqual(UserDefaults.standard.object(forKey: key) as? Date, synced)
        XCTAssertFalse(account.blocksDismissal)
        account.updateConnection(.offline)
        XCTAssertEqual(account.lastSyncedAt, synced)
        await account.signOut()
        XCTAssertNil(account.lastSyncedAt, "게스트 화면에 이전 계정의 동기화 시각을 표시하지 않음")
        XCTAssertEqual(account.messageContext, .management)
    }

    func testEmailAccountWithoutGoogleCannotReauthenticateWithGoogle() async throws {
        let client = stubClient()
        let vault = SessionVault(project: client.config.url.host!)
        defer { try? vault.clear() }
        let id = UUID()
        try vault.write(AccountSession(accessToken: "a", refreshToken: "r", expiresAt: Date().timeIntervalSince1970 + 3600,
                                       user: AccountUser(id: id, email: "me@example.com")))
        socialStub(id: id, challenge: { nil })
        let model = AppModel() // AccountModel holds AppModel unowned; keep it alive for the test.
        let account = AccountModel(model: model, client: client, initialConnection: .online, monitorConnectivity: false)
        await account.bootstrap()
        await account.refreshProviders()
        XCTAssertTrue(account.canSignIn(with: .google), "로그인 화면에서는 사용 가능")
        account.beginDeletion()
        XCTAssertTrue(account.canUseEmailForReauthentication, "예전 세션은 이메일 계정으로 간주")
        XCTAssertFalse(account.canSignIn(with: .google), "연결되지 않은 방법으로는 삭제 본인 확인 불가")
    }

    // MARK: - 일상 알림 '완료' 버튼

    func testDailyNotificationDoneOnlyChangesCurrentAccountOnce() throws {
        let accountID = UUID()
        let scope = try SharedStore.activate(userID: accountID)
        let day = "2026-10-05"
        let item = DailyItem(title: "독서", kind: .habit, startDate: DayKey.date(fromKey: day)!,
                             reminderTime: ReminderTime(hour: 21, minute: 0))
        var data = AppData.empty
        data.saveDailyItem(item)
        _ = try SharedStore.persistEdits(from: .empty, to: data, selection: scope)
        let generation = scope.generation.uuidString

        XCTAssertNil(try SharedStore.completeDailyFromNotification(itemID: item.id, day: day, generation: UUID().uuidString),
                     "다른 계정·이전 세대 알림은 기록하지 않음")
        XCTAssertTrue(try SharedStore.snapshot(userID: accountID).data.dailyCompletions.isEmpty)
        XCTAssertNil(try SharedStore.completeDailyFromNotification(itemID: item.id, day: "bad-day", generation: generation))

        let saved = try XCTUnwrap(try SharedStore.completeDailyFromNotification(itemID: item.id, day: day, generation: generation))
        XCTAssertEqual(saved.1, generation)
        let stored = try SharedStore.snapshot(userID: accountID)
        XCTAssertEqual(stored.data.dailyCompletions.count, 1)
        XCTAssertEqual(stored.data.dailyCompletions.first?.day, day)
        XCTAssertTrue(stored.dirty, "다음 연결 때 서버에 저장")
        XCTAssertNil(try SharedStore.completeDailyFromNotification(itemID: item.id, day: day, generation: generation),
                     "두 번 눌러도 완료가 취소되지 않음")
        XCTAssertEqual(try SharedStore.snapshot(userID: accountID).data.dailyCompletions.count, 1)
        XCTAssertFalse(saved.0.plannedReminders(now: DayKey.date(fromKey: day)!).contains { $0.day == day },
                       "완료한 날의 알림은 다시 예약하지 않음")

        // 계정을 바꾸면 이전 계정 알림의 버튼은 새 계정 기록을 바꾸지 못함
        _ = try SharedStore.activate(userID: UUID())
        XCTAssertNil(try SharedStore.completeDailyFromNotification(itemID: item.id, day: "2026-10-06", generation: generation))
    }
}
