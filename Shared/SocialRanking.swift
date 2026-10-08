import Foundation

// MARK: - 친구·그룹 경쟁: 서버 응답 형식과 순위 계산 (네트워크·화면과 분리해 검사 가능)

/// 서버(social_overview)가 돌려주는 내 정보·친구·그룹
struct SocialOverview: Decodable, Equatable {
    struct Profile: Decodable, Equatable {
        var nickname: String
        var friend_code: String
        var share_records: Bool
    }
    struct Friend: Decodable, Equatable, Identifiable {
        enum Status: String, Decodable { case friend, incoming, outgoing }
        var user_id: UUID
        var nickname: String
        var status: Status
        var id: UUID { user_id }
    }
    struct Member: Decodable, Equatable, Identifiable {
        var user_id: UUID
        var nickname: String
        var joined: Bool
        var id: UUID { user_id }
    }
    struct Group: Decodable, Equatable, Identifiable {
        var id: UUID
        var name: String
        var is_owner: Bool
        var joined: Bool
        var members: [Member]
    }
    var profile: Profile?
    var friends: [Friend]
    var groups: [Group]

    var acceptedFriends: [Friend] { friends.filter { $0.status == .friend } }
    var incomingRequests: [Friend] { friends.filter { $0.status == .incoming } }
    var outgoingRequests: [Friend] { friends.filter { $0.status == .outgoing } }
    var joinedGroups: [Group] { groups.filter(\.joined) }
    var groupInvites: [Group] { groups.filter { !$0.joined } }
}

/// 순위표의 원자료 한 줄 (social_leaderboard)
struct SocialEntry: Decodable, Equatable {
    var user_id: UUID
    var nickname: String
    var is_me: Bool
    var type_id: String
    var value: Double
    var extra_reps: Int
    var achieved_at: String  // yyyy-MM-dd

    var entry: RecordEntry {
        RecordEntry(typeID: type_id, date: DayKey.date(fromKey: achieved_at) ?? Date(timeIntervalSince1970: 0),
                    value: value, extraReps: extra_reps)
    }
}

/// 서버에 올리는 내 공통 종목 최고기록 한 줄
struct PublishedRecord: Encodable, Equatable {
    var type_id: String
    var value: Double
    var extra_reps: Int
    var achieved_at: String
}

struct RankedRow: Equatable, Identifiable {
    var rank: Int
    var userID: UUID
    var nickname: String
    var isMe: Bool
    var display: String
    var achievedAt: Date
    var id: UUID { userID }
}

enum SocialRanking {
    /// 종목 규칙(높을수록/낮을수록, 라운드형 점수)으로 정렬. 같은 점수는 같은 순위(1, 1, 3)이고
    /// 화면 순서는 먼저 달성한 사람 → 닉네임 순.
    static func rank(_ entries: [SocialEntry], for type: RecordType) -> [RankedRow] {
        let rows = entries.filter { $0.type_id == type.id }.map { ($0, $0.entry) }
        let sorted = rows.sorted { a, b in
            let sa = type.score(a.1), sb = type.score(b.1)
            if sa != sb { return type.lowerIsBetter ? sa < sb : sa > sb }
            if a.1.date != b.1.date { return a.1.date < b.1.date }
            return a.0.nickname < b.0.nickname
        }
        var result: [RankedRow] = []
        for (index, row) in sorted.enumerated() {
            let rank = index > 0 && type.score(sorted[index - 1].1) == type.score(row.1) ? result[index - 1].rank : index + 1
            result.append(RankedRow(rank: rank, userID: row.0.user_id, nickname: row.0.nickname, isMe: row.0.is_me,
                                    display: type.display(row.1), achievedAt: row.1.date))
        }
        return result
    }
}

extension AppData {
    /// 공개할 내 기록: 활성 공통 종목마다 기록 탭에 보이는 최고기록과 같은 값.
    /// 횟수 종목은 직접 기록과 운동 일지 중 높은 한 세트, 라운드형 등은 직접 기록 최고.
    func socialPublishPayload(catalog: [CatalogRecordType]) -> [PublishedRecord] {
        let all = exerciseRecords()
        return CatalogRecordType.sorted(catalog).filter(\.active).compactMap { definition in
            let type = definition.recordType
            if Self.acceptsWorkoutRepetitions(type),
               let combined = combinedBestSet(for: type, auto: exerciseRecords(for: type, in: all)) {
                return PublishedRecord(type_id: type.id, value: combined.value, extra_reps: 0,
                                       achieved_at: DayKey.key(combined.date))
            }
            guard let manual = self.best(type) else { return nil }
            return PublishedRecord(type_id: type.id, value: manual.value, extra_reps: manual.extraReps,
                                   achieved_at: DayKey.key(manual.date))
        }
    }
}
