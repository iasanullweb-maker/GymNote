import Foundation

// MARK: - 루틴

struct Exercise: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var sets: Int
    var detail: String      // 예: "10회", "1분", "최대의 70%"
    var restSeconds: Int    // 세트 사이 휴식 (0이면 타이머 안 켬)
}

struct DayPlan: Codable, Hashable {
    var title: String
    var exercises: [Exercise]

    var isRestDay: Bool { exercises.isEmpty }
    var totalSets: Int { exercises.reduce(0) { $0 + max($1.sets, 0) } }
}

// MARK: - 최고 기록

enum RecordKind: String, Codable, CaseIterable, Identifiable {
    case pushup, pullup, cindy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pushup: return "푸쉬업"
        case .pullup: return "풀업"
        case .cindy: return "신디"
        }
    }

    var hint: String {
        switch self {
        case .pushup, .pullup: return "한 세트 최대 반복 횟수"
        case .cindy: return "20분 AMRAP (풀업 5 · 푸쉬업 10 · 에어 스쿼트 15). 완료한 라운드와 추가 횟수를 적어."
        }
    }
}

struct RecordEntry: Codable, Identifiable, Hashable {
    static let cindyRepsPerRound = 30

    var id: UUID = UUID()
    var kind: RecordKind
    var date: Date
    var value: Int          // 횟수 (신디는 라운드)
    var extraReps: Int = 0  // 신디 추가 횟수

    var score: Int { kind == .cindy ? value * Self.cindyRepsPerRound + extraReps : value }
    var display: String { kind == .cindy ? "\(value)R + \(extraReps)" : "\(value)회" }
    var shortDisplay: String { kind == .cindy ? "\(value)R+\(extraReps)" : "\(value)" }
}

// MARK: - 하루 기록

struct DayLog: Codable, Hashable {
    var day: String                    // yyyy-MM-dd
    var doneSets: [String: Int] = [:]  // 운동 ID → 완료한 세트 수
}

// MARK: - 전체 데이터

struct AppData: Codable, Equatable {
    var week: [DayPlan]          // 0=일, 1=월 ... 6=토
    var records: [RecordEntry]
    var logs: [DayLog]
    var defaultRest: Int

    enum CodingKeys: String, CodingKey {
        case week, records, logs, defaultRest
    }

    init(week: [DayPlan], records: [RecordEntry] = [], logs: [DayLog] = [], defaultRest: Int = 90) {
        self.week = week
        self.records = records
        self.logs = logs
        self.defaultRest = defaultRest
        padWeek()
    }

    // 나중에 필드가 늘어나도 예전 저장 파일을 읽을 수 있게 하나씩 꺼냄
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        week = try c.decodeIfPresent([DayPlan].self, forKey: .week) ?? AppData.sample.week
        records = try c.decodeIfPresent([RecordEntry].self, forKey: .records) ?? []
        logs = try c.decodeIfPresent([DayLog].self, forKey: .logs) ?? []
        defaultRest = try c.decodeIfPresent(Int.self, forKey: .defaultRest) ?? 90
        padWeek()
    }

    private mutating func padWeek() {
        while week.count < 7 { week.append(DayPlan(title: "휴식", exercises: [])) }
        if week.count > 7 { week = Array(week.prefix(7)) }
    }
}

// MARK: - 날짜 도우미

enum DayKey {
    static let weekdayNames = ["일", "월", "화", "수", "목", "금", "토"]

    static func key(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func weekdayIndex(_ date: Date = Date()) -> Int {
        (Calendar.current.component(.weekday, from: date) + 6) % 7
    }

    static func weekdayName(_ date: Date = Date()) -> String {
        weekdayNames[weekdayIndex(date)]
    }
}

// MARK: - 로직

extension AppData {
    func plan(for date: Date = Date()) -> DayPlan {
        let i = DayKey.weekdayIndex(date)
        return week.indices.contains(i) ? week[i] : DayPlan(title: "휴식", exercises: [])
    }

    func doneSets(_ exercise: Exercise, on date: Date = Date()) -> Int {
        let key = DayKey.key(date)
        let raw = logs.first(where: { $0.day == key })?.doneSets[exercise.id.uuidString] ?? 0
        return min(max(raw, 0), max(exercise.sets, 0))
    }

    func progress(on date: Date = Date()) -> (done: Int, total: Int) {
        let p = plan(for: date)
        let done = p.exercises.reduce(0) { $0 + doneSets($1, on: date) }
        return (done, p.totalSets)
    }

    /// 다음에 할 세트 (휴식 타이머와 위젯에 표시)
    func nextUp(on date: Date = Date()) -> (title: String, info: String) {
        let p = plan(for: date)
        if p.isRestDay { return ("휴식일", "") }
        for exercise in p.exercises {
            let done = doneSets(exercise, on: date)
            if done < exercise.sets {
                return (exercise.name, "\(done + 1)/\(exercise.sets)세트 · \(exercise.detail)")
            }
        }
        return ("오늘 운동 끝!", "수고했어")
    }

    func best(_ kind: RecordKind) -> RecordEntry? {
        records.filter { $0.kind == kind }.max { $0.score < $1.score }
    }

    func entries(_ kind: RecordKind) -> [RecordEntry] {
        records.filter { $0.kind == kind }.sorted { $0.date < $1.date }
    }

    /// 세트 수를 delta만큼 바꿈. wrap이 true면 다 채운 상태에서 +1 할 때 0으로 돌아감 (위젯에서 되돌리기용)
    mutating func changeSets(_ exerciseID: UUID, by delta: Int, wrap: Bool = false, on date: Date = Date()) {
        guard let exercise = plan(for: date).exercises.first(where: { $0.id == exerciseID }) else { return }
        let key = DayKey.key(date)
        if !logs.contains(where: { $0.day == key }) {
            logs.append(DayLog(day: key))
        }
        guard let i = logs.firstIndex(where: { $0.day == key }) else { return }

        let current = doneSets(exercise, on: date)
        var next = current + delta
        if wrap && delta > 0 && current >= exercise.sets { next = 0 }
        logs[i].doneSets[exerciseID.uuidString] = min(max(next, 0), max(exercise.sets, 0))

        // 1년 넘은 기록은 정리
        if logs.count > 400 { logs.removeFirst(logs.count - 400) }
    }

    /// 기록을 추가하고, 신기록이면 true
    @discardableResult
    mutating func addRecord(_ entry: RecordEntry) -> Bool {
        let previous = best(entry.kind)
        records.append(entry)
        if let previous = previous { return entry.score > previous.score }
        return true
    }
}

// MARK: - 예시 루틴 (앱에서 수정 가능)

extension AppData {
    static var sample: AppData {
        func ex(_ name: String, _ sets: Int, _ detail: String, _ rest: Int) -> Exercise {
            Exercise(name: name, sets: sets, detail: detail, restSeconds: rest)
        }
        func upper() -> DayPlan {
            DayPlan(title: "상체", exercises: [
                ex("푸쉬업", 5, "최대의 70%", 90),
                ex("풀업", 5, "최대의 70%", 120),
                ex("딥스", 3, "10회", 90),
                ex("플랭크", 3, "1분", 60),
            ])
        }
        func lower() -> DayPlan {
            DayPlan(title: "하체·코어", exercises: [
                ex("에어 스쿼트", 5, "20회", 60),
                ex("런지", 3, "다리당 12회", 60),
                ex("행잉 레그레이즈", 3, "12회", 60),
            ])
        }
        let cindy = DayPlan(title: "신디", exercises: [
            ex("워밍업", 1, "10분", 0),
            ex("신디", 1, "20분 AMRAP", 0),
            ex("스트레칭", 1, "10분", 0),
        ])
        let test = DayPlan(title: "기록 테스트", exercises: [
            ex("푸쉬업 최대", 1, "최대 반복", 180),
            ex("풀업 최대", 1, "최대 반복", 180),
        ])
        let rest = DayPlan(title: "휴식", exercises: [])
        return AppData(week: [rest, upper(), lower(), cindy, upper(), lower(), test])
    }
}
