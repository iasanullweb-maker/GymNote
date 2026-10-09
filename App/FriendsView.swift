import SwiftUI
import UIKit

/// 친구 탭에서 기록 탭의 순위로, 기록 탭에서 친구 탭으로 이동할 때 쓰는 동작
private struct OpenFriendsTabKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var openFriendsTab: (() -> Void)? {
        get { self[OpenFriendsTabKey.self] }
        set { self[OpenFriendsTabKey.self] = newValue }
    }
}

/// 로그인·서버·연결 상태에 따라 안내를 보여 주고, 사용할 수 있으면 overview로 내용을 그린다.
private struct SocialGate<Content: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    @ViewBuilder var content: (SocialOverview) -> Content

    var body: some View {
        let social = model.social
        if !account.configured {
            Section { Text("계정 연결을 준비 중이에요.").foregroundStyle(.secondary) }
        } else if account.user == nil {
            Section {
                Label("로그인하면 친구와 공통 종목 기록을 겨룰 수 있어요", systemImage: "person.2.fill")
                Text("설정 탭 → 계정에서 로그인해 주세요. 기록은 닉네임을 정한 뒤부터 친구에게 보여요.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } else if social.unavailable {
            Section {
                Label("친구 기능 서버를 준비 중이에요", systemImage: "server.rack")
                Text("서버 설정이 끝나면 바로 사용할 수 있어요. 기기의 기록은 그대로예요.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } else if let overview = social.overview {
            content(overview)
        } else if !account.isOnline {
            Section { Label("친구 기능은 인터넷 연결이 필요해요", systemImage: "wifi.slash") }
        } else {
            Section { ProgressView("친구 정보를 불러오는 중…") }
        }
        if let message = social.message {
            Section { Text(message).font(.footnote) }
        }
    }
}

/// 친구 탭: 내 닉네임·친구 코드, 친구 추가·요청, 그룹 만들기·초대. 순위는 기록 탭 → 친구에서 본다.
struct FriendsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    @State private var nickname = ""
    @State private var share = true
    @State private var code = ""
    @State private var groupName = ""
    @State private var addingFriend = false
    @State private var creatingGroup = false
    @State private var renaming = false
    @State private var removing: SocialOverview.Friend?
    @State private var confirmingWithdrawal = false

    private var social: SocialModel { model.social }

    var body: some View {
        NavigationStack {
            List {
                SocialGate { overview in
                    if let profile = overview.profile {
                        profileSection(profile)
                        friendSections(overview)
                        groupSections(overview)
                        Section {
                            Label("순위는 기록 탭 → 친구에서 볼 수 있어요", systemImage: "trophy")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Section {
                            Button("친구 기능 탈퇴", role: .destructive) { confirmingWithdrawal = true }
                        } footer: {
                            Text("앱 계정과 개인 운동 기록은 유지돼요.")
                        }
                    } else {
                        onboarding
                    }
                }
            }
            .navigationTitle("친구")
            .disabled(social.working)
            .task(id: account.user?.id) { await social.refresh() }
            .onChange(of: account.user?.id) { _, _ in
                nickname = ""; share = true; code = ""; groupName = ""
                addingFriend = false; creatingGroup = false; renaming = false
                removing = nil; confirmingWithdrawal = false
            }
            .refreshable { await social.refresh() }
            .confirmationDialog("친구 기능에서 탈퇴할까요?", isPresented: $confirmingWithdrawal, titleVisibility: .visible) {
                Button("친구 기능 탈퇴", role: .destructive) {
                    Task {
                        if await social.withdraw() { nickname = ""; share = true }
                    }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("닉네임·친구 코드·친구 관계·그룹 참여·공개 기록이 삭제돼요. 그룹장은 다른 참여자에게 넘겨요. 앱 계정과 개인 운동 일지는 유지되며, 다시 가입할 수 있어요.")
            }
            .alert("친구 추가", isPresented: $addingFriend) {
                TextField("친구 코드 8자리", text: $code)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                Button("요청 보내기") { let value = code; Task { await social.sendFriendRequest(code: value) } }
                Button("취소", role: .cancel) {}
            } message: { Text("친구에게 받은 친구 코드를 입력해 주세요. 상대가 수락하면 서로의 공통 종목 기록이 보여요.") }
            .alert("그룹 만들기", isPresented: $creatingGroup) {
                TextField("그룹 이름 (예: 헬스 동아리)", text: $groupName)
                Button("만들기") { let value = groupName; Task { await social.createGroup(name: value) } }
                Button("취소", role: .cancel) {}
            } message: { Text("만든 뒤 친구를 초대할 수 있어요.") }
            .alert("닉네임 바꾸기", isPresented: $renaming) {
                TextField("닉네임", text: $nickname)
                Button("저장") {
                    let value = nickname, sharing = social.overview?.profile?.share_records ?? true
                    Task { await social.saveProfile(nickname: value, share: sharing) }
                }
                Button("취소", role: .cancel) {}
            }
            .confirmationDialog("친구를 끊을까요?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                                titleVisibility: .visible) {
                Button("친구 끊기", role: .destructive) {
                    if let friend = removing { Task { await social.remove(friend) } }
                    removing = nil
                }
            } message: { Text("서로의 기록이 더 이상 보이지 않아요. 함께 있는 그룹 순위에는 계속 나와요.") }
        }
    }

    // MARK: 처음 시작

    private var onboarding: some View {
        Section {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 34, weight: .semibold)).foregroundStyle(.orange)
                        .frame(width: 76, height: 76)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
                        .accessibilityHidden(true)
                    Text("친구와 기록 겨루기").font(.title.bold()).multilineTextAlignment(.center)
                    Text("닉네임을 정하고 친구와\n운동 기록을 함께 확인하세요.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("닉네임").font(.headline)
                    TextField("1~20자", text: $nickname)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(16).background(Color(uiColor: .secondarySystemGroupedBackground),
                                                in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel("친구 기능 닉네임")
                    Toggle("최고 기록 자동 공개", isOn: $share)
                    Text("친구·그룹원에게 닉네임과 공통 종목 최고 기록만 보여요. 이메일은 공개되지 않아요. 공개는 언제든 끌 수 있어요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button {
                    let value = nickname, sharing = share
                    Task { await social.saveProfile(nickname: value, share: sharing) }
                } label: {
                    Text("친구 기능 가입하기").font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 17)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 16))
                .disabled(!(1...20).contains(nickname.trimmingCharacters(in: .whitespacesAndNewlines).count))
            }
            .frame(maxWidth: 440).frame(maxWidth: .infinity).padding(.vertical, 24)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: 내 정보

    private func profileSection(_ profile: SocialOverview.Profile) -> some View {
        Section {
            LabeledContent("닉네임") {
                Button(profile.nickname) { nickname = profile.nickname; renaming = true }
            }
            LabeledContent("내 친구 코드") {
                Text(profile.friend_code).font(.body.monospaced().bold()).textSelection(.enabled)
            }
            HStack {
                Button { UIPasteboard.general.string = profile.friend_code; social.message = "친구 코드를 복사했어요." } label: {
                    Label("복사", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                ShareLink(item: "헬스노트 친구 코드: \(profile.friend_code)") { Label("공유", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.bordered)
            }
            Toggle("기록 자동 공개", isOn: Binding(
                get: { profile.share_records },
                set: { value in Task { await social.saveProfile(nickname: profile.nickname, share: value) } }))
        } header: {
            Text("내 정보")
        } footer: {
            Text(profile.share_records
                 ? "공통 종목 최고기록이 친구·그룹원에게 자동으로 보여요. 친구 코드를 알려 주면 친구 요청을 받을 수 있어요."
                 : "공개를 꺼서 내 기록은 다른 사람에게 보이지 않아요. 친구 기록은 계속 볼 수 있어요.")
        }
    }

    // MARK: 친구

    @ViewBuilder
    private func friendSections(_ overview: SocialOverview) -> some View {
        if !overview.incomingRequests.isEmpty {
            Section("받은 친구 요청") {
                ForEach(overview.incomingRequests) { friend in
                    HStack {
                        Label(friend.nickname, systemImage: "person.badge.plus")
                        Spacer()
                        Button("수락") { Task { await social.respond(to: friend, accept: true) } }.buttonStyle(.borderedProminent)
                        Button("거절") { Task { await social.respond(to: friend, accept: false) } }.buttonStyle(.bordered)
                    }
                }
            }
        }
        Section {
            Button { code = ""; addingFriend = true } label: {
                Label("친구 추가", systemImage: "person.badge.plus")
            }
            if overview.acceptedFriends.isEmpty {
                Text("아직 친구가 없어요. 친구 코드를 주고받아 추가해 보세요.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(overview.acceptedFriends) { friend in
                Label(friend.nickname, systemImage: "person.fill")
                    .swipeActions { Button("끊기", role: .destructive) { removing = friend } }
                    .contextMenu { Button("친구 끊기", role: .destructive) { removing = friend } }
            }
            ForEach(overview.outgoingRequests) { friend in
                HStack {
                    Label(friend.nickname, systemImage: "paperplane").foregroundStyle(.secondary)
                    Spacer()
                    Text("요청 보냄").font(.caption).foregroundStyle(.secondary)
                    Button("취소") { Task { await social.remove(friend) } }.buttonStyle(.borderless)
                }
            }
        } header: {
            Text("친구 \(overview.acceptedFriends.count)명")
        }
    }

    // MARK: 그룹

    @ViewBuilder
    private func groupSections(_ overview: SocialOverview) -> some View {
        if !overview.groupInvites.isEmpty {
            Section("받은 그룹 초대") {
                ForEach(overview.groupInvites) { group in
                    HStack {
                        Label(group.name, systemImage: "envelope.open")
                        Spacer()
                        Button("참여") { Task { await social.respond(to: group, accept: true) } }.buttonStyle(.borderedProminent)
                        Button("거절") { Task { await social.respond(to: group, accept: false) } }.buttonStyle(.bordered)
                    }
                }
            }
        }
        Section {
            ForEach(overview.joinedGroups) { group in
                NavigationLink {
                    GroupDetailView(groupID: group.id)
                } label: {
                    LabeledContent(group.name, value: "\(group.members.filter(\.joined).count)명")
                }
            }
            Button { groupName = ""; creatingGroup = true } label: { Label("그룹 만들기", systemImage: "person.3") }
        } header: {
            Text("그룹")
        } footer: {
            Text("그룹원은 내 친구 중에서 초대할 수 있어요. 같은 그룹이면 서로 친구가 아니어도 그룹 순위에서 기록이 보여요.")
        }
    }
}

/// 기록 탭의 '친구': 공통 종목 순위(내 친구 전체/그룹별). 친구 관리는 친구 탭에서 한다.
struct FriendRankingView: View {
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    @Environment(\.openFriendsTab) private var openFriendsTab

    private var social: SocialModel { model.social }
    private var types: [RecordType] { account.catalogTypes.filter(\.active).map(\.recordType) }

    var body: some View {
        List {
            SocialGate { overview in
                if overview.profile == nil {
                    Section {
                        Label("친구 탭에서 닉네임을 정하면 순위를 볼 수 있어요", systemImage: "person.2.fill")
                        if let openFriendsTab {
                            Button("친구 탭으로 가기", action: openFriendsTab)
                        }
                    }
                } else {
                    rankingSections(overview)
                }
            }
        }
        .task(id: account.user?.id) { await account.refreshRecordCatalog(); await social.refresh() }
        .refreshable { await account.refreshRecordCatalog(); await social.refresh() }
    }

    @ViewBuilder
    private func rankingSections(_ overview: SocialOverview) -> some View {
        Section {
            Picker("순위 보기", selection: Binding(get: { social.scope },
                                               set: { next in Task { await social.select(next) } })) {
                Text("내 친구 전체").tag(SocialModel.Scope.friends)
                ForEach(overview.joinedGroups) { group in
                    Text(group.name).tag(SocialModel.Scope.group(group.id))
                }
            }
            if overview.acceptedFriends.isEmpty && overview.joinedGroups.isEmpty {
                Text("친구 탭에서 친구를 추가하면 함께 순위가 보여요.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        ForEach(types) { type in
            Section {
                let rows = social.ranked(type)
                if rows.isEmpty {
                    Text("아직 공개된 기록이 없어요.").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(rows) { row in RankRow(row: row) }
            } header: {
                Text(type.name).font(.title3.bold()).textCase(nil)
            }
        }
    }
}

private struct RankRow: View {
    let row: RankedRow
    var body: some View {
        HStack(spacing: 12) {
            Text(row.rank <= 3 ? ["🥇", "🥈", "🥉"][row.rank - 1] : "\(row.rank)")
                .font(.headline.monospacedDigit()).frame(width: 34)
            Text(row.nickname + (row.isMe ? " (나)" : "")).fontWeight(row.isMe ? .bold : .regular).lineLimit(1)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.display).font(.headline)
                Text(row.achievedAt, format: .dateTime.month().day()).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .listRowBackground(row.isMe ? Color.orange.opacity(0.12) : nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.rank)위 \(row.nickname)\(row.isMe ? ", 나" : "") \(row.display)")
    }
}

/// 그룹 상세: 그룹원·초대 대기, 친구 초대, 나가기
private struct GroupDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let groupID: UUID
    @State private var confirmLeave = false

    private var social: SocialModel { model.social }

    var body: some View {
        let overview = social.overview
        let group = overview?.groups.first { $0.id == groupID }
        List {
            if let group, let overview {
                Section("그룹원") {
                    ForEach(group.members) { member in
                        HStack {
                            Label(member.nickname, systemImage: member.joined ? "person.fill" : "hourglass")
                            Spacer()
                            if !member.joined { Text("초대함").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                let memberIDs = Set(group.members.map(\.user_id))
                let invitable = overview.acceptedFriends.filter { !memberIDs.contains($0.user_id) }
                Section {
                    if invitable.isEmpty {
                        Text("초대할 수 있는 친구가 없어요. 먼저 친구를 추가해 주세요.").font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(invitable) { friend in
                        Button { Task { await social.invite(friend, to: group) } } label: {
                            Label("\(friend.nickname) 초대", systemImage: "person.badge.plus")
                        }
                    }
                } header: { Text("친구 초대") }
                Section {
                    Button("그룹 나가기", role: .destructive) { confirmLeave = true }
                } footer: {
                    Text(group.is_owner ? "그룹장이 나가면 가장 먼저 들어온 그룹원이 그룹장이 되고, 아무도 없으면 그룹이 사라져요." : "")
                }
                .confirmationDialog("'\(group.name)' 그룹에서 나갈까요?", isPresented: $confirmLeave, titleVisibility: .visible) {
                    Button("나가기", role: .destructive) {
                        Task { await social.leave(group); dismiss() }
                    }
                }
            } else {
                Text("그룹 정보를 찾을 수 없어요.").foregroundStyle(.secondary)
            }
            if let message = social.message { Section { Text(message).font(.footnote) } }
        }
        .navigationTitle(group?.name ?? "그룹")
        .disabled(social.working)
        .refreshable { await social.refresh() }
    }
}
