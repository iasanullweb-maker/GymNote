import SwiftUI
import UIKit

/// 기록 탭의 '친구': 내 닉네임·친구 코드, 공통 종목 순위(친구 전체/그룹), 친구·그룹 관리.
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

    private var social: SocialModel { model.social }
    private var types: [RecordType] { account.catalogTypes.filter(\.active).map(\.recordType) }

    var body: some View {
        List {
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
                    Text("서버 설정이 끝나면 이 화면에서 바로 사용할 수 있어요. 기기의 기록은 그대로예요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else if let overview = social.overview {
                if let profile = overview.profile {
                    profileSection(profile)
                    rankingSections(overview)
                    friendSections(overview)
                    groupSections(overview)
                } else {
                    onboarding
                }
            } else if !account.isOnline {
                Section { Label("친구 순위는 인터넷 연결이 필요해요", systemImage: "wifi.slash") }
            } else {
                Section { ProgressView("친구 정보를 불러오는 중…") }
            }
            if let message = social.message {
                Section { Text(message).font(.footnote) }
            }
        }
        .disabled(social.working)
        .task(id: account.user?.id) { await social.refresh() }
        .refreshable { await social.refresh() }
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

    // MARK: 처음 시작

    private var onboarding: some View {
        Section {
            TextField("닉네임 (1~20자)", text: $nickname)
            Toggle("공통 종목 최고기록 자동 공개", isOn: $share)
            Button("친구 기능 시작하기") {
                let value = nickname, sharing = share
                Task { await social.saveProfile(nickname: value, share: sharing) }
            }
            .disabled(nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text("친구와 기록 겨루기")
        } footer: {
            Text("친구에게는 닉네임과 공통 종목(푸쉬업·풀업 등) 최고기록만 보여요. 이메일은 보이지 않아요. 공개를 켜 두면 기록 탭의 최고 기록이 바뀔 때 자동으로 올라가고, 끄면 서버에서 지워져요.")
        }
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
                 ? "공통 종목 최고기록이 친구·그룹원에게 자동으로 보여요."
                 : "공개를 꺼서 내 기록은 다른 사람에게 보이지 않아요. 친구 기록은 계속 볼 수 있어요.")
        }
    }

    // MARK: 순위

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

    // MARK: 친구

    @ViewBuilder
    private func friendSections(_ overview: SocialOverview) -> some View {
        Section {
            ForEach(overview.incomingRequests) { friend in
                HStack {
                    Label("\(friend.nickname)님의 친구 요청", systemImage: "person.badge.plus")
                    Spacer()
                    Button("수락") { Task { await social.respond(to: friend, accept: true) } }.buttonStyle(.borderedProminent)
                    Button("거절") { Task { await social.respond(to: friend, accept: false) } }.buttonStyle(.bordered)
                }
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
            Button { code = ""; addingFriend = true } label: { Label("친구 코드로 추가", systemImage: "plus") }
        } header: {
            Text("친구 \(overview.acceptedFriends.count)명")
        }
    }

    // MARK: 그룹

    @ViewBuilder
    private func groupSections(_ overview: SocialOverview) -> some View {
        Section {
            ForEach(overview.groupInvites) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Label("'\(group.name)' 그룹 초대", systemImage: "envelope.open")
                    HStack {
                        Button("참여") { Task { await social.respond(to: group, accept: true) } }.buttonStyle(.borderedProminent)
                        Button("거절") { Task { await social.respond(to: group, accept: false) } }.buttonStyle(.bordered)
                    }
                }
            }
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
