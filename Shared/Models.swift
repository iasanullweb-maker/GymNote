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

/// 기록 종목 (앱에서 추가/삭제/순서 변경 가능. 위에 있는 3개가 위젯에 표시됨)
struct RecordType: Codable, Identifiable, Hashable {
    enum Style: String, Codable, CaseIterable {
        case count   // 숫자 하나 (횟수, kg, 초 등)
        case rounds  // 라운드 + 추가 횟수 (AMRAP)
    }

    var id: String = UUID().uuidString
    var name: String
    var unit: String = "회"
    var style: Style = .count
    var repsPerRound: Int = 30
    var lowerIsBetter: Bool = false
    var hint: String = ""

    static let defaults: [RecordType] = [
        RecordType(id: "pushup", name: "푸쉬업", hint: "한 세트 최대 반복 횟수"),
        RecordType(id: "pullup", name: "풀업", hint: "한 세트 최대 반복 횟수"),
        RecordType(id: "cindy", name: "신디", unit: "", style: .rounds, repsPerRound: 30,
                   hint: "20분 AMRAP (풀업 5 · 푸쉬업 10 · 에어 스쿼트 15). 완료한 라운드와 추가 횟수를 적어."),
    ]

    func score(_ e: RecordEntry) -> Double {
        style == .rounds ? e.value * Double(max(repsPerRound, 1)) + Double(e.extraReps) : e.value
    }

    func isBetter(_ a: RecordEntry, than b: RecordEntry) -> Bool {
        lowerIsBetter ? score(a) < score(b) : score(a) > score(b)
    }

    func display(_ e: RecordEntry) -> String {
        style == .rounds ? "\(Int(e.value))R + \(e.extraReps)" : "\(Self.number(e.value))\(unit)"
    }

    func shortDisplay(_ e: RecordEntry) -> String {
        if style == .rounds { return "\(Int(e.value))R+\(e.extraReps)" }
        return Self.number(e.value) + (unit == "회" ? "" : unit)
    }

    static func number(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }
}

struct RecordEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var typeID: String
    var date: Date
    var value: Double       // 기록 (라운드 방식이면 라운드 수)
    var extraReps: Int = 0  // 라운드 방식의 추가 횟수

    enum CodingKeys: String, CodingKey {
        case id, typeID, kind, date, value, extraReps
    }

    init(typeID: String, date: Date, value: Double, extraReps: Int = 0) {
        self.typeID = typeID
        self.date = date
        self.value = value
        self.extraReps = extraReps
    }

    // 예전 버전("kind": "pushup")으로 저장된 기록도 읽음
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        typeID = try c.decodeIfPresent(String.self, forKey: .typeID)
            ?? c.decode(String.self, forKey: .kind)
        date = try c.decode(Date.self, forKey: .date)
        value = try c.decode(Double.self, forKey: .value)
        extraReps = try c.decodeIfPresent(Int.self, forKey: .extraReps) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(typeID, forKey: .typeID)
        try c.encode(date, forKey: .date)
        try c.encode(value, forKey: .value)
        try c.encode(extraReps, forKey: .extraReps)
    }
}

// MARK: - 하루 기록

struct DayLog: Codable, Hashable {
    var day: String                    // yyyy-MM-dd
    var doneSets: [String: Int] = [:]  // 운동 ID → 완료한 세트 수
}

// MARK: - 전체 데이터

struct AppData: Codable, Equatable {
    var week: [DayPlan]          // 0=일, 1=월 ... 6=토
    var recordTypes: [RecordType]
    var records: [RecordEntry]
    var logs: [DayLog]
    var defaultRest: Int
    var restSound: Bool          // 휴식 끝 알림 소리 (기본: 끔)

    enum CodingKeys: String, CodingKey {
        case week, recordTypes, records, logs, defaultRest, restSound
    }

    init(week: [DayPlan], recordTypes: [RecordType] = RecordType.defaults, records: [RecordEntry] = [],
         logs: [DayLog] = [], defaultRest: Int = 90, restSound: Bool = false) {
        self.week = week
        self.recordTypes = recordTypes
        self.records = records
        self.logs = logs
        self.defaultRest = defaultRest
        self.restSound = restSound
        padWeek()
    }

    // 나중에 필드가 늘어나도 예전 저장 파일을 읽을 수 있게 하나씩 꺼냄
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        week = try c.decodeIfPresent([DayPlan].self, forKey: .week) ?? AppData.sample.week
        recordTypes = try c.decodeIfPresent([RecordType].self, forKey: .recordTypes) ?? RecordType.defaults
        records = try c.decodeIfPresent([RecordEntry].self, forKey: .records) ?? []
        logs = try c.decodeIfPresent([DayLog].self, forKey: .logs) ?? []
        defaultRest = try c.decodeIfPresent(Int.self, forKey: .defaultRest) ?? 90
        restSound = try c.decodeIfPresent(Bool.self, forKey: .restSound) ?? false
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

    func recordType(_ id: String) -> RecordType? {
        recordTypes.first { $0.id == id }
    }

    func best(_ type: RecordType) -> RecordEntry? {
        records.filter { $0.typeID == type.id }.reduce(nil) { current, e in
            guard let current = current else { return e }
            return type.isBetter(e, than: current) ? e : current
        }
    }

    func entries(_ type: RecordType) -> [RecordEntry] {
        records.filter { $0.typeID == type.id }.sorted { $0.date < $1.date }
    }

    /// 위젯에 보여줄 종목 (목록 맨 위부터)
    func widgetTypes(_ count: Int = 3) -> [RecordType] {
        Array(recordTypes.prefix(count))
    }

    mutating func updateRecord(_ entry: RecordEntry) {
        if let i = records.firstIndex(where: { $0.id == entry.id }) {
            records[i] = entry
        }
    }

    /// 종목과 그 종목의 기록을 모두 삭제
    mutating func deleteRecordType(_ id: String) {
        recordTypes.removeAll { $0.id == id }
        records.removeAll { $0.typeID == id }
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
        guard let type = recordType(entry.typeID) else { return false }
        let previous = best(type)
        records.append(entry)
        if let previous = previous { return type.isBetter(entry, than: previous) }
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
