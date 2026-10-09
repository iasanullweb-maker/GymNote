import AuthenticationServices
import Foundation
import Observation
import Network

enum AccountConnection { case checking, offline, online }
enum AccountMessageContext: Equatable { case authentication, backup, management }

@Observable
@MainActor
final class AccountModel {
    private(set) var session: AccountSession?
    private(set) var busy = false
    private(set) var operationTitle = "기기 기록을 불러오는 중…"
    private(set) var messageContext: AccountMessageContext = .authentication
    private(set) var lastSyncedAt: Date?
    private(set) var initialized = false
    private(set) var needsLogin = false
    private(set) var pendingEmail: String?
    private(set) var sentAt: Date?
    private(set) var conflict: CloudWorkout?
    private(set) var message: String?
    private(set) var syncStatus = "기기에 저장 중"
    private(set) var cloudChecked = false
    private(set) var connection: AccountConnection
    private(set) var guestSelected = false
    private(set) var catalogTypes = CatalogRecordType.defaults
    private(set) var catalogLoading = false
    private(set) var catalogMessage: String?
    private(set) var catalogFetchedAt: Date?
    private var catalogAdminUserID: UUID?
    var canManageCatalog: Bool {
        user != nil && catalogAdminUserID == user?.id && isOnline && !needsLogin && !deleting
    }
    /// Providers the Supabase project reports as enabled. Unknown (offline/failed) means none.
    private(set) var availableProviders: Set<SocialProvider> = []
    @ObservationIgnored private unowned let model: AppModel
    @ObservationIgnored private let client: AuthClient?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var syncRequested = false
    @ObservationIgnored private var generation = UUID()
    private var deleting = false
    @ObservationIgnored private let connectivity = NWPathMonitor()
    /// Live app: watch the network and refresh enabled providers automatically. Tests call refreshProviders() directly.
    @ObservationIgnored private let monitorsEnvironment: Bool

    var configured: Bool { client != nil }
    var user: AccountUser? { session?.user }
    var isReauthenticating: Bool { needsLogin || deleting }
    var isDeleting: Bool { deleting }
    var blocksDismissal: Bool { busy && messageContext != .backup }
    func resendSeconds(at date: Date = Date()) -> Int {
        sentAt.map { max(0, Int(ceil(60 - date.timeIntervalSince($0)))) } ?? 0
    }
    private func startOperation(_ title: String, context: AccountMessageContext) {
        operationTitle = title
        messageContext = context
        message = nil
        busy = true
    }
    func clearMessage() { message = nil }
    func closeAccountScreen() {
        guard !blocksDismissal else { return }
        if deleting { cancelDeletion() }
        else { resetCode() }
    }
    /// Methods this account can re-authenticate with. Older cached sessions lack provider data: assume email.
    var accountProviders: [String] { (user?.providers.isEmpty ?? true) ? ["email"] : user!.providers }
    var canUseEmailForReauthentication: Bool { !deleting || accountProviders.contains("email") }
    func canSignIn(with provider: SocialProvider) -> Bool {
        guard configured, isOnline, availableProviders.contains(provider) else { return false }
        return !deleting || accountProviders.contains(provider.rawValue)
    }
    var isOnline: Bool { connection == .online }
    var showsWelcome: Bool { initialized && configured && isOnline && user == nil && !guestSelected }
    var modeDescription: String {
        if !isOnline { return "오프라인 모드 · 기기에 저장 중" }
        return user == nil ? "게스트 모드 · 기기에 저장 중" : syncStatus
    }
    var hasGuestRecords: Bool {
        guard let data = try? SharedStore.snapshot(userID: nil).data else { return false }
        return !data.records.isEmpty || !data.workouts.isEmpty || !data.logs.isEmpty
            || data.activeWorkout != nil || !data.scheduledPlans.isEmpty || !data.exerciseLibrary.isEmpty
            || !data.dailyItems.isEmpty || !data.dailyCompletions.isEmpty
    }
    private func importConsentKey(_ id: UUID) -> String {
        "com.gymnote.importConsent.\(client?.config.url.host ?? "unconfigured").\(id.uuidString)"
    }
    private var vault: SessionVault? { client.map { SessionVault(project: $0.config.url.host!) } }
    private func lastSyncKey(_ id: UUID) -> String {
        "com.gymnote.lastSync.\(client?.config.url.host ?? "unconfigured").\(id.uuidString)"
    }
    private func recordSuccessfulSync() {
        lastSyncedAt = Date()
        if let id = user?.id { UserDefaults.standard.set(lastSyncedAt, forKey: lastSyncKey(id)) }
    }
    var canImport: Bool {
        guard cloudChecked, let id = user?.id else { return false }
        return (try? SharedStore.snapshot(userID: id).importedGuest) == false
    }

    init(model: AppModel, client: AuthClient? = AuthConfiguration.current.map { AuthClient(config: $0) },
         initialConnection: AccountConnection = .checking, monitorConnectivity: Bool = true) {
        self.model = model
        self.client = client
        if let cache = SharedStore.recordCatalog(), cache.project == client?.config.url.host {
            catalogTypes = cache.types
            catalogFetchedAt = cache.fetchedAt
        }
        connection = initialConnection
        monitorsEnvironment = monitorConnectivity
        connectivity.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied && (path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet))
            Task { @MainActor [weak self] in self?.updateConnection(connected ? .online : .offline) }
        }
        if monitorConnectivity { connectivity.start(queue: DispatchQueue(label: "com.gymnote.connectivity")) }
    }
    deinit { connectivity.cancel(); syncTask?.cancel() }

    func bootstrap() async {
        guard !initialized else { return }
        startOperation("기기 기록을 불러오는 중…", context: .management)
        defer { initialized = true; finishOperation(); scheduleSync(); autoRefreshProviders() }
        do {
            if let stored = try vault?.read() {
                session = stored
                lastSyncedAt = UserDefaults.standard.object(forKey: lastSyncKey(stored.user.id)) as? Date
                try await model.switchAccount(stored.user.id)
            }
        } catch {
            session = nil
            message = AccountError.storage.localizedDescription
        }
        // A cached account may work offline; all cloud access still requires server authentication.
    }

    func updateConnection(_ next: AccountConnection) {
        connection = next
        if isOnline { scheduleSync(); autoRefreshProviders() }
        else {
            // Do not cancel an in-flight upload: it may already have committed on the server.
            if !busy { syncTask?.cancel() }
            syncStatus = "오프라인 모드 · 연결되면 자동 저장"
        }
    }

    func continueAsGuest() { guestSelected = true; resetCode() }

    private func autoRefreshProviders() {
        guard monitorsEnvironment else { return }
        Task { [weak self] in
            await self?.refreshProviders()
            await self?.refreshRecordCatalog()
        }
    }

    func refreshRecordCatalog() async {
        guard isOnline, !catalogLoading, !(busy && messageContext == .management), let client else { return }
        catalogLoading = true
        catalogAdminUserID = nil
        defer { catalogLoading = false }
        do {
            let types = try await client.recordCatalog()
            let cache = RecordCatalogCache(project: client.config.url.host!, types: types, fetchedAt: Date())
            catalogTypes = CatalogRecordType.sorted(types)
            catalogFetchedAt = cache.fetchedAt
            catalogMessage = nil
            do { try SharedStore.saveRecordCatalog(cache) }
            catch { catalogMessage = "최신 공통 종목을 불러왔지만 기기에 보관하지 못했어요." }
            await refreshCatalogAdmin()
        } catch {
            catalogMessage = "공통 종목을 갱신하지 못했어요. 저장된 목록을 사용합니다."
        }
    }

    private func refreshCatalogAdmin() async {
        guard !busy, session != nil, !needsLogin, !deleting, let client else { return }
        startOperation("관리자 권한을 확인하는 중…", context: .backup)
        defer { finishOperation() }
        let operation = generation
        do {
            let current = try await validSession()
            if try await client.isCatalogAdmin(token: current.accessToken),
               operation == generation, session?.user.id == current.user.id {
                catalogAdminUserID = current.user.id
            }
        } catch { catalogAdminUserID = nil }
    }

    /// Serialize with account operations so rotating a refresh token cannot race a backup or logout.
    func saveCatalogType(_ type: CatalogRecordType) async -> Bool {
        guard canManageCatalog, !busy, !catalogLoading, let client else { return false }
        startOperation("공통 종목을 저장하는 중…", context: .management)
        defer { finishOperation() }
        do {
            let current = try await validSession()
            let saved = try await client.saveCatalogType(type, token: current.accessToken)
            var next = catalogTypes.filter { $0.id != saved.id }
            next.append(saved)
            next = CatalogRecordType.sorted(next)
            catalogTypes = next
            catalogFetchedAt = Date()
            catalogMessage = nil
            do { try SharedStore.saveRecordCatalog(RecordCatalogCache(project: client.config.url.host!, types: next, fetchedAt: Date())) }
            catch { catalogMessage = "서버에 종목을 저장했지만 기기에 보관하지 못했어요." }
            return true
        } catch AccountError.conflict {
            catalogMessage = "다른 관리자가 수정했어요. 목록을 새로고침한 뒤 다시 열어 주세요."
        } catch AccountError.unauthorized {
            catalogAdminUserID = nil
            catalogMessage = "관리자 권한 또는 로그인 상태를 확인해 주세요."
        } catch {
            catalogMessage = "저장을 확인하지 못했어요. 목록을 새로고침해 확인해 주세요."
        }
        return false
    }

    /// Buttons are enabled only for providers the server confirms. Failure keeps them disabled.
    func refreshProviders() async {
        guard initialized, isOnline, let client else { return }
        if let providers = try? await client.enabledProviders() { availableProviders = providers }
    }

    private func requireConnection() -> Bool {
        guard isOnline else {
            message = "이 계정 작업은 Wi-Fi 연결이 필요해요. 기존 기록은 기기에 계속 저장됩니다."
            return false
        }
        return true
    }

    func scheduleSync() {
        guard initialized, isOnline, session != nil, !needsLogin, !deleting, conflict == nil else { return }
        // Never cancel a running upload: the server may commit it even if its response is cancelled.
        if busy { syncRequested = true; return }
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 1_500_000_000) }
            catch { return }
            guard !Task.isCancelled else { return }
            await self?.synchronize()
        }
    }

    private func finishOperation() {
        busy = false
        if syncRequested {
            syncRequested = false
            scheduleSync()
        }
    }

    func sendCode(email raw: String, createUser: Bool, consent: Bool) async {
        guard !busy, let client else { return }
        messageContext = .authentication
        guard requireConnection() else { return }
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.count <= 254, email.contains("@"), !email.contains(where: { $0.isWhitespace }),
              !createUser || consent else { message = AccountError.invalidInput.localizedDescription; return }
        if let sentAt, Date().timeIntervalSince(sentAt) < 60 { message = "인증번호 재발송은 60초 후 가능합니다."; return }
        if deleting, email.lowercased() != user?.email?.lowercased() { message = "현재 계정의 이메일을 입력해 주세요."; return }
        startOperation("인증번호 보내는 중…", context: .authentication)
        defer { finishOperation() }
        do {
            try await client.sendCode(email: email, createUser: createUser && !deleting)
            pendingEmail = email
            sentAt = Date()
            message = "로그인 가능한 이메일이라면 인증번호를 보냈어요. 메일함을 확인해 주세요."
        } catch AccountError.invalidInput {
            // Never reveal whether a login-only email has an existing account.
            pendingEmail = email
            sentAt = Date()
            message = "로그인 가능한 이메일이라면 인증번호를 보냈어요. 메일함을 확인해 주세요."
        } catch { show(error) }
    }

    /// Verification is also the fresh authentication step required before deleting an account.
    func verify(code: String, importDeviceRecords: Bool = false) async {
        guard !busy, let client, let email = pendingEmail else { return }
        messageContext = .authentication
        guard requireConnection() else { return }
        guard code.count == 6, code.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            message = AccountError.invalidInput.localizedDescription; return
        }
        startOperation("인증번호 확인 중…", context: .authentication)
        defer { finishOperation() }
        do {
            let verified = try await client.verify(email: email, code: code)
            try await completeSignIn(verified, importDeviceRecords: importDeviceRecords)
        } catch { show(error) }
    }

    /// Google/Apple through Supabase hosted OAuth. `authenticate` presents the system authentication
    /// browser (ASWebAuthenticationSession) and returns the callback URL it received.
    /// Used for first login, expired-session login and re-authentication before account deletion.
    func signIn(with provider: SocialProvider, importDeviceRecords: Bool = false,
                authenticate: (URL) async throws -> URL) async {
        guard !busy, let client else { return }
        messageContext = .authentication
        guard requireConnection() else { return }
        guard canSignIn(with: provider) else {
            message = (deleting && availableProviders.contains(provider) ? AccountError.wrongAccount : AccountError.providerUnavailable).localizedDescription
            return
        }
        startOperation(deleting ? "본인 확인 중…" : "로그인 중…", context: .authentication)
        defer { finishOperation() }
        do {
            let attempt = try client.beginOAuth(provider)
            let callback: URL
            do { callback = try await authenticate(attempt.url) }
            catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin { throw AccountError.cancelled }
            catch is CancellationError { throw AccountError.cancelled }
            catch let error as AccountError { throw error }
            catch { throw AccountError.browserUnavailable }
            let code = try AuthClient.authorizationCode(from: callback)
            let verified = try await client.exchange(code: code, verifier: attempt.verifier)
            try await completeSignIn(verified, importDeviceRecords: importDeviceRecords)
        } catch { show(error) }
    }

    /// Shared by email OTP and social login. Records are keyed only by the server-verified user UUID,
    /// never by email, and guest records are copied only with explicit consent.
    private func completeSignIn(_ verified: AccountSession, importDeviceRecords: Bool) async throws {
        guard let client else { throw AccountError.notConfigured }
        let wasGuest = model.selection.userID == nil
        var identity = try await client.user(token: verified.accessToken)
        guard identity.id == verified.user.id else { throw AccountError.unauthorized }
        if deleting, identity.id != user?.id {
            // Deletion re-authentication must prove the same account; revoke the session we just created.
            try? await client.signOut(token: verified.accessToken)
            throw AccountError.wrongAccount
        }
        if identity.email == nil { identity.email = verified.user.email }
        var accepted = verified
        accepted.user = identity
        let previous = session
        let beforeImport = try SharedStore.snapshot(userID: identity.id)
        try vault?.write(accepted)
        if model.selection.userID != identity.id {
            cloudChecked = false
            conflict = nil
            try await model.switchAccount(identity.id)
        }
        session = accepted
        lastSyncedAt = UserDefaults.standard.object(forKey: lastSyncKey(identity.id)) as? Date
        if let previous, previous.user.id == identity.id, previous.accessToken != accepted.accessToken,
           previous.expiresAt > Date().timeIntervalSince1970 + 30 {
            // Re-authentication creates a new server session; end the replaced one when still possible.
            try? await client.signOut(token: previous.accessToken)
        }
        if wasGuest, !deleting, importDeviceRecords {
            try SharedStore.importGuest(selection: model.selection)
            if !beforeImport.importedGuest, beforeImport.serverVersion == 0, !beforeImport.dirty {
                UserDefaults.standard.set(true, forKey: importConsentKey(identity.id))
            }
            model.reload()
        }
        needsLogin = false
        pendingEmail = nil
        generation = UUID()
        message = deleting ? "본인 확인을 마쳤어요. 계정 삭제를 다시 눌러 완료해 주세요."
            : (wasGuest && importDeviceRecords ? "로그인했어요. 기기 기록을 가져왔고, 연결되면 서버에 이어서 저장합니다."
                : "로그인했어요. 기존 기기 기록은 설정에서 가져올 수 있어요.")
        if deleting { deletionVerifiedAt = Date() }
        else { scheduleSync() }
    }

    func resetCode() { pendingEmail = nil; message = nil }

    @ObservationIgnored private var refreshTask: Task<AccountSession, Error>?

    /// 만료가 가까우면 갱신. 동시에 여러 곳(백업 동기화·친구 기능)에서 불러도 갱신 요청은 하나만 보내
    /// 회전된 refresh token을 두 번 쓰지 않는다.
    private func validSession() async throws -> AccountSession {
        guard let current = session, let client else { throw AccountError.unauthorized }
        guard current.expiresAt < Date().timeIntervalSince1970 + 60 else { return current }
        if let pending = refreshTask { return try await pending.value }
        let task = Task { @MainActor [vault] () throws -> AccountSession in
            let refreshed = try await client.refresh(current)
            guard refreshed.user.id == current.user.id else { throw AccountError.unauthorized }
            try vault?.write(refreshed) // Save rotated refresh tokens before any subsequent request.
            return refreshed
        }
        refreshTask = task
        defer { refreshTask = nil }
        let refreshed = try await task.value
        if session?.user.id == refreshed.user.id { session = refreshed }
        return refreshed
    }

    /// 친구·그룹 기능용: 로그인·연결 상태를 확인하고 유효한 토큰을 돌려준다. 계정 작업 화면의 진행 표시는 바꾸지 않는다.
    func socialAccess() async throws -> (client: AuthClient, token: String, userID: UUID) {
        guard let client, session != nil else { throw AccountError.unauthorized }
        guard isOnline else { throw URLError(.notConnectedToInternet) }
        guard !needsLogin, !deleting else { throw AccountError.unauthorized }
        let current = try await validSession()
        return (client, current.accessToken, current.user.id)
    }

    func synchronize() async {
        guard !busy, isOnline, !needsLogin, !deleting, conflict == nil, session != nil, let client else { return }
        startOperation("기록 동기화 중…", context: .backup)
        defer { finishOperation() }
        let operation = generation
        let selection = model.selection
        do {
            let current = try await validSession()
            guard current.user.id == selection.userID else { throw AccountError.stale }
            var local = try SharedStore.snapshot(userID: selection.userID)
            let remote = try await client.download(token: current.accessToken)
            guard generation == operation, model.selection == selection else { throw AccountError.stale }
            cloudChecked = true
            if UserDefaults.standard.bool(forKey: importConsentKey(current.user.id)) {
                if let remote, local.serverVersion == 0, remote.version != local.serverVersion {
                    if remote.payload.hasImportConflict(with: local.data) {
                        conflict = remote
                        syncStatus = "다른 기기의 변경 확인 필요"
                        return
                    }
                    try SharedStore.mergeInitialImport(remote.payload, version: remote.version, revision: local.revision, selection: selection)
                    local = try SharedStore.snapshot(userID: selection.userID)
                    model.reload()
                }
                UserDefaults.standard.removeObject(forKey: importConsentKey(current.user.id))
            }
            if let remote, remote.version != local.serverVersion {
                if local.dirty {
                    conflict = remote
                    syncStatus = "다른 기기의 변경 확인 필요"
                    return
                }
                try SharedStore.replaceWithCloud(remote.payload, version: remote.version, revision: local.revision, selection: selection)
                model.reload()
            } else if local.dirty {
                let version = try await client.upload(local, token: current.accessToken)
                guard generation == operation, model.selection == selection else { throw AccountError.stale }
                try SharedStore.acknowledge(version: version, revision: local.revision, selection: selection)
            }
            syncStatus = "동기화 완료"
            recordSuccessfulSync()
            if try SharedStore.snapshot(userID: selection.userID).dirty { scheduleSync() }
        } catch AccountError.conflict {
            // An upload raced another device; re-read before offering explicit conflict resolution.
            syncStatus = "다른 기기의 변경 확인 필요"
            scheduleSync()
        } catch { show(error, marksSessionInvalid: true); syncStatus = "기기에 보관 중 · 동기화 대기" }
    }

    func importGuest() async {
        guard !busy, canImport, !needsLogin, !deleting, conflict == nil else { return }
        messageContext = .backup
        do {
            try SharedStore.importGuest(selection: model.selection)
            model.reload()
            message = "기기 기록을 가져왔어요. 원본 게스트 기록은 유지됩니다."
            scheduleSync()
        } catch { show(error) }
    }

    /// Both choices preserve a local backup; replacing the cloud uses the version the user reviewed.
    func resolveConflict(useCloud: Bool) async {
        guard !busy, !needsLogin, let remote = conflict, let client else { return }
        messageContext = .backup
        guard requireConnection() else { return }
        startOperation(useCloud ? "서버 기록 불러오는 중…" : "서버 기록 교체 중…", context: .backup)
        defer { finishOperation() }
        let selection = model.selection
        do {
            let local = try SharedStore.snapshot(userID: selection.userID)
            if useCloud {
                try SharedStore.replaceWithCloud(remote.payload, version: remote.version, revision: local.revision, selection: selection)
            } else {
                let current = try await validSession()
                try SharedStore.backupCloud(remote.payload, selection: selection)
                var upload = local
                upload.serverVersion = remote.version
                let version = try await client.upload(upload, token: current.accessToken)
                try SharedStore.acknowledge(version: version, revision: local.revision, selection: selection)
            }
            conflict = nil
            model.reload()
            syncStatus = "동기화 완료"
            recordSuccessfulSync()
            scheduleSync()
        } catch AccountError.conflict {
            conflict = nil
            message = "다른 기기가 다시 수정했어요. 최신 기록을 다시 확인합니다."
            scheduleSync()
        } catch { show(error, marksSessionInvalid: true) }
    }

    func signOut() async {
        guard !busy else { return }
        startOperation("로그아웃 중…", context: .management)
        syncTask?.cancel()
        defer { finishOperation() }
        var serverLogoutFailed = !isOnline && session != nil
        if isOnline, let client, session != nil {
            do {
                let fresh = try await validSession()
                try await client.signOut(token: fresh.accessToken)
            } catch { serverLogoutFailed = true }
        }
        do {
            try vault?.clear()
            if let id = session?.user.id { UserDefaults.standard.removeObject(forKey: importConsentKey(id)) }
            session = nil
            lastSyncedAt = nil
            cloudChecked = false
            generation = UUID()
            conflict = nil
            pendingEmail = nil
            sentAt = nil
            deleting = false
            deletionVerifiedAt = nil
            needsLogin = false
            guestSelected = true
            syncStatus = "기기에 저장 중"
            try await model.switchAccount(nil)
            message = serverLogoutFailed ? "이 기기에서 로그아웃했어요. 서버 세션 종료는 확인하지 못했어요. 계정 기록은 다음 로그인까지 숨겨집니다." : "로그아웃했어요. 계정 기록은 다음 로그인까지 숨겨집니다."
        } catch { show(error) }
    }

    private var deletionVerifiedAt: Date?
    var readyToDelete: Bool { deletionIsVerified(at: Date()) }
    func deletionIsVerified(at date: Date) -> Bool {
        deleting && (deletionVerifiedAt.map { date.timeIntervalSince($0) < 300 } ?? false)
    }
    func expireDeletionVerification(at date: Date = Date()) {
        guard !busy, deleting, deletionVerifiedAt != nil, !deletionIsVerified(at: date) else { return }
        deletionVerifiedAt = nil
        pendingEmail = nil
        messageContext = .authentication
        message = "본인 확인이 만료됐어요. 다시 본인 확인을 해 주세요."
    }
    func beginDeletion() {
        guard !busy, user != nil, !needsLogin, isOnline else { return }
        deleting = true
        pendingEmail = nil
        deletionVerifiedAt = nil
        syncTask?.cancel()
        messageContext = .authentication
        message = accountProviders.contains("email")
            ? "계정 삭제를 위해 이메일 인증번호나 연결된 로그인 방법으로 본인 확인을 해 주세요."
            : "계정 삭제를 위해 연결된 로그인 방법으로 다시 로그인해 본인 확인을 해 주세요."
    }
    func cancelDeletion() {
        guard !busy, deleting else { return }
        deleting = false
        deletionVerifiedAt = nil
        resetCode()
        scheduleSync()
    }

    func deleteAccount() async {
        guard !busy, let client, let current = session else { return }
        messageContext = .authentication
        guard requireConnection() else { return }
        guard readyToDelete else {
            deletionVerifiedAt = nil
            message = "본인 확인이 만료됐어요. 다시 본인 확인을 해 주세요."
            return
        }
        startOperation("계정 삭제 중…", context: .authentication)
        defer { finishOperation() }
        do {
            try await client.deleteAccount(token: current.accessToken)
            UserDefaults.standard.removeObject(forKey: ManualWorkoutDraft.storageKey(userID: current.user.id))
            UserDefaults.standard.removeObject(forKey: importConsentKey(current.user.id))
            var cleanupError: Error?
            do { try vault?.clear() } catch { cleanupError = error }
            session = nil
            lastSyncedAt = nil
            cloudChecked = false
            generation = UUID()
            conflict = nil
            deleting = false
            deletionVerifiedAt = nil
            pendingEmail = nil
            needsLogin = false
            syncStatus = "기기에 저장 중"
            // Purge this account even if the unrelated guest file cannot be decoded.
            do { try await model.switchAccount(nil) } catch { cleanupError = error }
            do { try SharedStore.eraseAccount(current.user.id) } catch { cleanupError = error }
            if let cleanupError { throw cleanupError }
            message = "계정과 서버 기록을 삭제했어요. 게스트 원본 기록은 유지됩니다."
        } catch {
            deletionVerifiedAt = nil
            show(error, marksSessionInvalid: true)
        }
    }

    private func show(_ error: Error, marksSessionInvalid: Bool = false) {
        if let accountError = error as? AccountError {
            message = accountError.localizedDescription
            if marksSessionInvalid, case .unauthorized = accountError { needsLogin = session != nil }
        } else if error is URLError {
            message = "인터넷 연결을 확인해 주세요. 기기의 기록은 그대로 보관됩니다."
        } else { message = AccountError.storage.localizedDescription }
    }
}
