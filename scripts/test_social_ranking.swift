import Foundation

@main
struct SocialRankingChecks {
    static func main() throws {
        func at(_ month: Int, _ day: Int) -> Date {
            Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day, hour: 18))!
        }
        func entry(_ name: String, _ type: String, _ value: Double, _ extra: Int = 0, day: String, me: Bool = false) -> SocialEntry {
            SocialEntry(user_id: UUID(), nickname: name, is_me: me, type_id: type, value: value, extra_reps: extra, achieved_at: day)
        }
        let catalog = CatalogRecordType.defaults
        let push = catalog[0].recordType, cindy = catalog[2].recordType

        // 높을수록 좋은 종목: 같은 점수는 같은 순위, 먼저 달성한 사람이 위
        let rows = SocialRanking.rank([
            entry("민수", push.id, 35, day: "2026-10-04"),
            entry("수혁", push.id, 40, day: "2026-10-05", me: true),
            entry("지훈", push.id, 35, day: "2026-10-02"),
            entry("다른 종목", cindy.id, 99, day: "2026-10-01"),
        ], for: push)
        assert(rows.map(\.nickname) == ["수혁", "지훈", "민수"])
        assert(rows.map(\.rank) == [1, 2, 2], "\(rows.map(\.rank))")
        assert(rows[0].isMe && rows[0].display == "40회")

        // 라운드형: 라운드×라운드당 횟수 + 추가 횟수로 비교
        let rounds = SocialRanking.rank([
            entry("A", cindy.id, 12, 5, day: "2026-10-01"),
            entry("B", cindy.id, 11, 29, day: "2026-10-01"),
            entry("C", cindy.id, 12, 10, day: "2026-10-03"),
        ], for: cindy)
        assert(rounds.map(\.nickname) == ["C", "A", "B"] && rounds[0].display == "12R + 10")

        // 낮을수록 좋은 종목
        let timed = RecordType(id: "common-run-v1", name: "달리기", unit: "초", lowerIsBetter: true)
        let fast = SocialRanking.rank([entry("느림", timed.id, 300, day: "2026-10-01"),
                                       entry("빠름", timed.id, 250, day: "2026-10-01")], for: timed)
        assert(fast.map(\.nickname) == ["빠름", "느림"] && fast.map(\.rank) == [1, 2])
        assert(SocialRanking.rank([], for: push).isEmpty)

        // 횟수·라운드의 소수와 숨은 추가 횟수는 경쟁에서 제외한다.
        assert(push.requiresWholeValue && cindy.requiresWholeValue)
        assert(push.acceptsValue(40) && !push.acceptsValue(40.004))
        assert(!cindy.acceptsValue(12.9) && !push.acceptsValue(.infinity))
        assert(!timed.requiresWholeValue && timed.acceptsValue(12.34))
        let weighted = RecordType(id: "common-weight-v1", name: "무게", unit: "kg")
        assert(weighted.acceptsValue(72.5))
        assert(SocialRanking.rank([
            entry("정상", push.id, 40, day: "2026-10-01"),
            entry("소수", push.id, 40.004, day: "2026-10-01"),
            entry("추가 횟수", push.id, 40, 1, day: "2026-10-01"),
        ], for: push).map(\.nickname) == ["정상"])
        assert(SocialRanking.rank([
            entry("정상", cindy.id, 12, 29, day: "2026-10-01"),
            entry("소수", cindy.id, 12.9, day: "2026-10-01"),
            entry("범위 초과", cindy.id, 12, 30, day: "2026-10-01"),
        ], for: cindy).map(\.nickname) == ["정상"])

        // 공개 값 = 기록 탭에 보이는 값: 횟수 종목은 직접 기록과 운동 일지 중 높은 한 세트, 라운드형은 직접 기록
        var data = AppData(week: Array(repeating: DayPlan(title: "휴식", exercises: []), count: 7))
        assert(data.socialPublishPayload(catalog: catalog).isEmpty, "기록이 없으면 공개할 것도 없음")
        data.records = [RecordEntry(typeID: push.id, date: at(10, 1), value: 30),
                        RecordEntry(typeID: cindy.id, date: at(10, 2), value: 12, extraReps: 7),
                        RecordEntry(typeID: "pushup", date: at(9, 1), value: 99)] // 예전 개인 종목은 공개하지 않음
        var payload = data.socialPublishPayload(catalog: catalog)
        assert(payload == [PublishedRecord(type_id: push.id, value: 30, extra_reps: 0, achieved_at: "2026-10-01"),
                           PublishedRecord(type_id: cindy.id, value: 12, extra_reps: 7, achieved_at: "2026-10-02")], "\(payload)")
        let originalRecords = data.records
        data.records += [RecordEntry(typeID: push.id, date: at(10, 3), value: 40.004),
                         RecordEntry(typeID: cindy.id, date: at(10, 3), value: 12.9)]
        assert(data.socialPublishPayload(catalog: catalog) == payload, "소수 최고기록 대신 다음 유효 정수 기록을 공개")
        assert(data.records.count == originalRecords.count + 2, "개인 소수 기록은 삭제하거나 반올림하지 않음")
        data.records = originalRecords
        let exercise = Exercise(name: "푸쉬업", sets: 2, detail: "10회")
        var session = WorkoutSession(startedAt: at(10, 5), plan: DayPlan(title: "상체", exercises: [exercise]))
        session.completedSets[exercise.id.uuidString] = 2
        session.actualReps[exercise.id.uuidString] = [33, 28]
        session.endedAt = at(10, 5)
        data.workouts = [session]
        // 공통 종목 정의로 계산(기록 탭과 같은 방식)
        var display = data
        display.recordTypes = catalog.map(\.recordType)
        payload = display.socialPublishPayload(catalog: catalog)
        assert(payload.first == PublishedRecord(type_id: push.id, value: 33, extra_reps: 0, achieved_at: "2026-10-05"), "운동 일지 33회가 직접 기록 30회보다 높음")
        // 사용 중단한 종목은 공개하지 않음
        var retired = catalog
        retired[0].active = false
        assert(!display.socialPublishPayload(catalog: retired).contains { $0.type_id == push.id })

        // 서버 응답 해석
        let overview = try JSONDecoder().decode(SocialOverview.self, from: Data("""
        {"profile":{"nickname":"수혁","friend_code":"ABCD2345","share_records":true},
         "friends":[{"user_id":"00000000-0000-0000-0000-000000000002","nickname":"민수","status":"friend"},
                    {"user_id":"00000000-0000-0000-0000-000000000003","nickname":"지훈","status":"incoming"},
                    {"user_id":"00000000-0000-0000-0000-000000000004","nickname":"하늘","status":"outgoing"}],
         "groups":[{"id":"00000000-0000-0000-0000-0000000000aa","name":"헬스 동아리","is_owner":true,"joined":true,
                    "members":[{"user_id":"00000000-0000-0000-0000-000000000001","nickname":"수혁","joined":true}]},
                   {"id":"00000000-0000-0000-0000-0000000000bb","name":"반 친구들","is_owner":false,"joined":false,"members":[]}]}
        """.utf8))
        assert(overview.acceptedFriends.map(\.nickname) == ["민수"] && overview.incomingRequests.count == 1 && overview.outgoingRequests.count == 1)
        assert(overview.joinedGroups.map(\.name) == ["헬스 동아리"] && overview.groupInvites.map(\.name) == ["반 친구들"])
        let empty = try JSONDecoder().decode(SocialOverview.self, from: Data(#"{"profile":null,"friends":[],"groups":[]}"#.utf8))
        assert(empty.profile == nil && empty.friends.isEmpty)
        print("Social ranking checks passed: ties, rounds, lower-is-better, publish values, retired types, overview decoding")
    }
}
