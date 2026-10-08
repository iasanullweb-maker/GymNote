import Foundation
import Observation
import Network

enum AccountConnection { case checking, offline, online }

@Observable
@MainActor
final class AccountModel {
    private(set) var session: AccountSession?
    private(set) var busy = false
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
    @ObservationIgnored private unowned let model: AppModel
    @ObservationIgnored private let client: AuthClient?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var syncRequested = false
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var deleting = false
    @ObservationIgnored private let connectivity = NWPathMonitor()

    var configured: Bool { client != nil }
    var user: AccountUser? { session?.user }
    var isReauthenticating: Bool { needsLogin || deleting }
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
    }
    private func importConsentKey(_ id: UUID) -> String {
        "com.gymnote.importConsent.\(client?.config.url.host ?? "unconfigured").\(id.uuidString)"
    }
    private var vault: SessionVault? { client.map { SessionVault(project: $0.config.url.host!) } }
    var canImport: Bool {
        guard cloudChecked, let id = user?.id else { return false }
        return (try? SharedStore.snapshot(userID: id).importedGuest) == false
    }

    init(model: AppModel, client: AuthClient? = AuthConfiguration.current.map { AuthClient(config: $0) },
         initialConnection: AccountConnection = .checking, monitorConnectivity: Bool = true) {
        self.model = model
        self.client = client
        connection = initialConnection
        connectivity.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied && (path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet))
            Task { @MainActor [weak self] in self?.updateConnection(connected ? .online : .offline) }
        }
        if monitorConnectivity { connectivity.start(queue: DispatchQueue(label: "com.gymnote.connectivity")) }
    }
    deinit { connectivity.cancel(); syncTask?.cancel() }

    func bootstrap() async {
        guard !initialized else { return }
        busy = true
        defer { initialized = true; finishOperation(); scheduleSync() }
        do {
            if let stored = try vault?.read() {
                session = stored
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
        if isOnline { scheduleSync() }
        else {
            // Do not cancel an in-flight upload: it may already have committed on the server.
            if !busy { syncTask?.cancel() }
            syncStatus = "오프라인 모드 · 연결되면 자동 저장"
        }
    }

    func continueAsGuest() { guestSelected = true; resetCode() }

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
        guard requireConnection() else { return }
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.count <= 254, email.contains("@"), !email.contains(where: { $0.isWhitespace }),
              !createUser || consent else { message = AccountError.invalidInput.localizedDescription; return }
        if let sentAt, Date().timeIntervalSince(sentAt) < 60 { message = "인증번호 재발송은 60초 후 가능합니다."; return }
        if deleting, email.lowercased() != user?.email?.lowercased() { message = "현재 계정의 이메일을 입력해 주세요."; return }
        busy = true
        message = nil
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
        guard requireConnection() else { return }
        guard code.count == 6, code.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            message = AccountError.invalidInput.localizedDescription; return
        }
        busy = true
        defer { finishOperation() }
        do {
            let wasGuest = model.selection.userID == nil
            let verified = try await client.verify(email: email, code: code)
            let identity = try await client.user(token: verified.accessToken)
            guard identity.id == verified.user.id, (!deleting || identity.id == user?.id) else { throw AccountError.unauthorized }
            let beforeImport = try SharedStore.snapshot(userID: identity.id)
            try vault?.write(verified)
            if model.selection.userID != identity.id {
                cloudChecked = false
                conflict = nil
                try await model.switchAccount(identity.id)
            }
            session = verified
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
        } catch { show(error) }
    }

    func resetCode() { pendingEmail = nil; message = nil }

    private func validSession() async throws -> AccountSession {
        guard var current = session, let client else { throw AccountError.unauthorized }
        if current.expiresAt < Date().timeIntervalSince1970 + 60 {
            let refreshed = try await client.refresh(current)
            guard refreshed.user.id == current.user.id else { throw AccountError.unauthorized }
            try vault?.write(refreshed) // Save rotated refresh tokens before any subsequent request.
            session = refreshed
            current = refreshed
        }
        return current
    }

    func synchronize() async {
        guard !busy, isOnline, !needsLogin, !deleting, conflict == nil, session != nil, let client else { return }
        busy = true
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
            if try SharedStore.snapshot(userID: selection.userID).dirty { scheduleSync() }
        } catch AccountError.conflict {
            // An upload raced another device; re-read before offering explicit conflict resolution.
            syncStatus = "다른 기기의 변경 확인 필요"
            scheduleSync()
        } catch { show(error, marksSessionInvalid: true); syncStatus = "기기에 보관 중 · 동기화 대기" }
    }

    func importGuest() async {
        guard !busy, canImport, !needsLogin, !deleting, conflict == nil else { return }
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
        guard requireConnection() else { return }
        busy = true
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
            scheduleSync()
        } catch AccountError.conflict {
            conflict = nil
            message = "다른 기기가 다시 수정했어요. 최신 기록을 다시 확인합니다."
            scheduleSync()
        } catch { show(error, marksSessionInvalid: true) }
    }

    func signOut() async {
        guard !busy else { return }
        busy = true
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

    @ObservationIgnored private var deletionVerifiedAt: Date?
    var readyToDelete: Bool { deletionVerifiedAt.map { Date().timeIntervalSince($0) < 300 } ?? false }
    func beginDeletion() {
        guard !busy else { return }
        deleting = true
        pendingEmail = nil
        sentAt = nil
        deletionVerifiedAt = nil
        syncTask?.cancel()
        message = "계정 삭제를 위해 현재 이메일로 인증번호를 받아 본인 확인을 해 주세요."
    }
    func cancelDeletion() { deleting = false; deletionVerifiedAt = nil; resetCode(); scheduleSync() }

    func deleteAccount() async {
        guard !busy, let client, let current = session else { return }
        guard requireConnection() else { return }
        guard readyToDelete else {
            deletionVerifiedAt = nil
            message = "본인 확인이 만료됐어요. 인증번호를 다시 받아 확인해 주세요."
            return
        }
        busy = true
        defer { finishOperation() }
        do {
            try await client.deleteAccount(token: current.accessToken)
            UserDefaults.standard.removeObject(forKey: importConsentKey(current.user.id))
            var cleanupError: Error?
            do { try vault?.clear() } catch { cleanupError = error }
            session = nil
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
