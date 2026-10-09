import Foundation
import Observation

/// 친구·그룹 경쟁. 서버가 권한을 모두 확인하고, 앱은 화면 상태와 자동 공개만 관리한다.
/// 공개는 닉네임을 정한 뒤부터 자동이며(공개 끄기 가능), 기록이 바뀌면 잠시 모았다가 한 번 올린다.
@Observable
@MainActor
final class SocialModel {
    enum Scope: Hashable { case friends, group(UUID) }

    private(set) var overview: SocialOverview?
    private(set) var entries: [Scope: [SocialEntry]] = [:]
    private(set) var loading = false
    private(set) var working = false
    private(set) var unavailable = false
    var message: String?
    var scope: Scope = .friends

    @ObservationIgnored private unowned let model: AppModel
    @ObservationIgnored private var publishTask: Task<Void, Never>?
    @ObservationIgnored private var loadedFor: UUID?
    @ObservationIgnored private var revision = 0

    init(model: AppModel) { self.model = model }

    private var account: AccountModel { model.account }
    var signedIn: Bool { account.user != nil }
    var hasProfile: Bool { overview?.profile != nil }
    /// 친구 탭 배지: 받은 친구 요청 + 그룹 초대
    var pendingCount: Int {
        guard let overview, loadedFor == account.user?.id else { return 0 }
        return overview.incomingRequests.count + overview.groupInvites.count
    }

    private func publishedKey(_ user: UUID) -> String { "com.gymnote.social.published.\(user.uuidString)" }
    /// 닉네임을 정하고 공개를 켠 계정인지(친구 화면을 열지 않은 실행에서도 자동 공개하기 위해 기억)
    private func sharingKey(_ user: UUID) -> String { "com.gymnote.social.sharing.\(user.uuidString)" }
    private func rememberSharing(_ latest: SocialOverview, for user: UUID) {
        UserDefaults.standard.set(latest.profile?.share_records == true, forKey: sharingKey(user))
    }

    /// 계정이 바뀌면 이전 계정의 친구 정보가 남지 않게 비운다.
    private func resetIfAccountChanged(_ user: UUID) {
        guard loadedFor != user else { return }
        overview = nil
        entries = [:]
        scope = .friends
        loadedFor = user
    }

    /// 내 정보·친구·그룹과 현재 선택한 순위를 새로 불러온다.
    /// quiet: 앱 시작·복귀 때 배지용으로 조용히 불러온다(실패해도 메시지를 띄우지 않음).
    func refresh(quiet: Bool = false) async {
        guard signedIn, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let access = try await account.socialAccess()
            resetIfAccountChanged(access.userID)
            let requestRevision = revision
            let latest = try await access.client.socialOverview(token: access.token)
            guard account.user?.id == access.userID, requestRevision == revision else { return }
            overview = latest
            unavailable = false
            rememberSharing(latest, for: access.userID)
            if case .group(let id) = scope, !latest.joinedGroups.contains(where: { $0.id == id }) { scope = .friends }
            if latest.profile != nil { await publish(force: false) }
            try await loadLeaderboard(scope, access: access)
        } catch {
            if quiet {
                if case AccountError.featureUnavailable = error { unavailable = true }
            } else {
                show(error)
            }
        }
    }

    func select(_ next: Scope) async {
        scope = next
        guard signedIn, hasProfile else { return }
        do { try await loadLeaderboard(next, access: account.socialAccess()) } catch { show(error) }
    }

    private func loadLeaderboard(_ target: Scope, access: (client: AuthClient, token: String, userID: UUID)) async throws {
        guard overview?.profile != nil else { return }
        let requestRevision = revision
        var group: UUID?
        if case .group(let id) = target { group = id }
        let rows = try await access.client.leaderboard(group: group, token: access.token)
        guard account.user?.id == access.userID, requestRevision == revision else { return }
        entries[target] = rows
    }

    func ranked(_ type: RecordType) -> [RankedRow] {
        SocialRanking.rank(entries[scope] ?? [], for: type)
    }

    // MARK: 동작

    /// Remove only social membership. Private account records are untouched.
    @discardableResult
    func withdraw() async -> Bool {
        guard !working else { return false }
        working = true
        revision += 1
        publishTask?.cancel()
        message = nil
        defer { working = false }
        do {
            let access = try await account.socialAccess()
            guard try await access.client.withdrawSocial(token: access.token) else { throw AccountError.server }
            guard account.user?.id == access.userID else { return false }
            revision += 1
            overview = SocialOverview(profile: nil, friends: [], groups: [])
            entries = [:]
            scope = .friends
            loadedFor = access.userID
            UserDefaults.standard.removeObject(forKey: publishedKey(access.userID))
            UserDefaults.standard.set(false, forKey: sharingKey(access.userID))
            message = "친구 기능에서 탈퇴했어요. 개인 운동 기록은 그대로예요."
            return true
        } catch {
            show(error)
            return false
        }
    }

    /// 공통 실행 틀: 진행 중 표시, 오류 메시지, 끝나면 목록 새로고침.
    private func perform(_ success: String?, _ action: (AuthClient, String) async throws -> Void) async {
        guard !working else { return }
        working = true
        message = nil
        defer { working = false }
        do {
            let access = try await account.socialAccess()
            try await action(access.client, access.token)
            if let success { message = success }
        } catch { show(error); return }
        await refresh()
    }

    func saveProfile(nickname raw: String, share: Bool) async {
        let nickname = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...20).contains(nickname.count) else { message = "닉네임은 1~20자로 정해 주세요."; return }
        let turningOff = overview?.profile?.share_records == true && !share
        await perform(turningOff ? "기록 공개를 껐어요. 서버에 올린 기록도 지웠어요." : nil) { client, token in
            _ = try await client.saveSocialProfile(nickname: nickname, share: share, token: token)
        }
        if let id = account.user?.id { UserDefaults.standard.removeObject(forKey: publishedKey(id)) }
        if share { await publish(force: true) }
    }

    func sendFriendRequest(code raw: String) async {
        let code = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard code.count == 8 else { message = "친구 코드 8자리를 입력해 주세요."; return }
        var result = ""
        await perform(nil) { client, token in result = try await client.sendFriendRequest(code: code, token: token) }
        switch result {
        case "sent": message = "친구 요청을 보냈어요. 상대가 수락하면 서로 기록이 보여요."
        case "accepted": message = "상대도 요청을 보내 둬서 바로 친구가 됐어요."
        case "already_friends": message = "이미 친구예요."
        case "self": message = "내 친구 코드예요."
        case "not_found": message = "그 코드의 사용자를 찾지 못했어요."
        default: break
        }
    }

    func respond(to friend: SocialOverview.Friend, accept: Bool) async {
        await perform(accept ? "\(friend.nickname)님과 친구가 됐어요." : nil) { client, token in
            _ = try await client.respondFriendRequest(from: friend.user_id, accept: accept, token: token)
        }
    }

    func remove(_ friend: SocialOverview.Friend) async {
        await perform(nil) { client, token in _ = try await client.removeFriend(friend.user_id, token: token) }
    }

    func createGroup(name raw: String) async {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...30).contains(name.count) else { message = "그룹 이름은 1~30자로 정해 주세요."; return }
        var created: UUID?
        await perform("그룹을 만들었어요. 친구를 초대해 보세요.") { client, token in
            created = try await client.createGroup(name: name, token: token)
        }
        if let created { await select(.group(created)) }
    }

    func invite(_ friend: SocialOverview.Friend, to group: SocialOverview.Group) async {
        await perform("\(friend.nickname)님을 초대했어요. 수락하면 그룹 순위에 나와요.") { client, token in
            _ = try await client.inviteToGroup(group.id, user: friend.user_id, token: token)
        }
    }

    func respond(to group: SocialOverview.Group, accept: Bool) async {
        await perform(accept ? "'\(group.name)' 그룹에 들어갔어요." : nil) { client, token in
            _ = try await client.respondGroupInvite(group.id, accept: accept, token: token)
        }
        if accept { await select(.group(group.id)) }
    }

    func leave(_ group: SocialOverview.Group) async {
        if scope == .group(group.id) { scope = .friends }
        await perform("'\(group.name)' 그룹에서 나왔어요.") { client, token in
            _ = try await client.leaveGroup(group.id, token: token)
        }
    }

    // MARK: 자동 공개

    /// 기록이 바뀌면 잠시 기다렸다가 공개한다(연속 수정은 한 번으로).
    func schedulePublish() {
        guard signedIn else { return }
        publishTask?.cancel()
        publishTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.publish(force: false)
        }
    }

    /// 공통 종목 최고기록을 올린다. 마지막으로 올린 내용과 같으면 보내지 않는다.
    /// 닉네임을 정하지 않았거나 공개를 껐으면 서버가 아무것도 저장하지 않는다.
    func publish(force: Bool) async {
        guard signedIn, account.isOnline, let user = account.user?.id else { return }
        let sharing = (loadedFor == user ? overview : nil).map { $0.profile?.share_records == true }
            ?? UserDefaults.standard.bool(forKey: sharingKey(user))
        guard sharing else { return }
        let payload = model.data.socialPublishPayload(catalog: account.catalogTypes)
        guard let encoded = try? JSONEncoder().encode(payload) else { return }
        let signature = String(decoding: encoded, as: UTF8.self)
        do {
            let access = try await account.socialAccess()
            let key = publishedKey(access.userID)
            if !force, UserDefaults.standard.string(forKey: key) == signature { return }
            _ = try await access.client.publishRecords(payload, token: access.token)
            guard account.user?.id == access.userID else { return }
            UserDefaults.standard.set(signature, forKey: key)
        } catch AccountError.featureUnavailable {
            unavailable = true
        } catch {
            // 자동 공개 실패는 조용히 넘기고 다음 변경·새로고침 때 다시 시도한다.
        }
    }

    private func show(_ error: Error) {
        if case AccountError.featureUnavailable = error { unavailable = true; return }
        if error is URLError { message = "인터넷 연결을 확인해 주세요."; return }
        if case AccountError.unauthorized = error {
            message = "권한이 없거나 로그인이 만료됐어요. 설정 → 계정에서 다시 로그인해 주세요."; return
        }
        message = (error as? AccountError)?.localizedDescription ?? AccountError.server.localizedDescription
    }
}
