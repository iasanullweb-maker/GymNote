import Foundation

// MARK: - 루틴

struct Exercise: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var sets: Int
    var detail: String      // 예: "10회", "1분", "최대의 70%"
    /// 예전 버전의 운동별 휴식. 지금은 쓰지 않고 설정의 기본 휴식(AppData.defaultRest) 하나로 통일.
    /// 예전 저장 파일·계정 동기화와 호환되도록 필드만 유지한다.
    var restSeconds: Int = 0

    init(id: UUID = UUID(), name: String, sets: Int, detail: String, restSeconds: Int = 0) {
        self.id = id
        self.name = name
        self.sets = sets
        self.detail = detail
        self.restSeconds = restSeconds
    }

    private enum CodingKeys: String, CodingKey { case id, name, sets, detail, restSeconds }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        sets = try c.decode(Int.self, forKey: .sets)
        detail = try c.decode(String.self, forKey: .detail)
        restSeconds = try c.decodeIfPresent(Int.self, forKey: .restSeconds) ?? 0
    }
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

// 운동을 시작할 때 계획을 복사해 저장. 이후 계획을 수정해도 일지는 유지됨.
struct WorkoutSession: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var startedAt: Date
    var endedAt: Date?
    var plan: DayPlan
    var completedSets: [String: Int] = [:]

    var day: String { DayKey.key(startedAt) }
    var done: Int { plan.exercises.reduce(0) { $0 + doneSets($1) } }
    var total: Int { plan.totalSets }
    func doneSets(_ exercise: Exercise) -> Int {
        min(max(completedSets[exercise.id.uuidString] ?? 0, 0), max(exercise.sets, 0))
    }
}

// MARK: - 전체 데이터

struct AppData: Codable, Equatable {
    var week: [DayPlan]          // 0=일, 1=월 ... 6=토
    var recordTypes: [RecordType]
    var records: [RecordEntry]
    var logs: [DayLog]
    var defaultRest: Int
    var restSound: Bool          // 휴식 끝 알림 소리 (기본: 끔)
    var restStep: Int = 15       // 운동 탭 휴식 −/+ 한 번에 바뀌는 초 (5초 단위, 최소 5초)
    var scheduledPlans: [String: DayPlan] = [:] // 날짜별 일정, 자동으로 반복하지 않음
    var exerciseLibrary: [Exercise] = []
    var activeWorkout: WorkoutSession?
    var workouts: [WorkoutSession] = []
    var dailyItems: [DailyItem] = []
    var dailyCompletions: [DailyCompletion] = []

    enum CodingKeys: String, CodingKey {
        case week, recordTypes, records, logs, defaultRest, restSound, restStep, scheduledPlans, exerciseLibrary, activeWorkout, workouts, dailyItems, dailyCompletions
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
        migrateSchedule()
        seedExerciseLibrary()
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
        restStep = try c.decodeIfPresent(Int.self, forKey: .restStep) ?? 15
        activeWorkout = try c.decodeIfPresent(WorkoutSession.self, forKey: .activeWorkout)
        workouts = try c.decodeIfPresent([WorkoutSession].self, forKey: .workouts) ?? []
        dailyItems = try c.decodeIfPresent([DailyItem].self, forKey: .dailyItems) ?? []
        dailyCompletions = try c.decodeIfPresent([DailyCompletion].self, forKey: .dailyCompletions) ?? []
        padWeek()
        if let saved = try c.decodeIfPresent([String: DayPlan].self, forKey: .scheduledPlans) {
            scheduledPlans = saved
        } else {
            migrateSchedule()
        }
        if let saved = try c.decodeIfPresent([Exercise].self, forKey: .exerciseLibrary) {
            exerciseLibrary = saved
        } else {
            seedExerciseLibrary()
        }
    }

    private mutating func migrateSchedule() {
        for date in DayKey.weekDates(containing: Date()) {
            scheduledPlans[DayKey.key(date)] = week[DayKey.weekdayIndex(date)]
        }
    }

    private mutating func seedExerciseLibrary() {
        var names = Set<String>()
        exerciseLibrary = week.flatMap(\.exercises).filter { names.insert($0.name).inserted }
            .map { exercise in
                var copy = exercise
                copy.id = UUID()
                return copy
            }
    }

    private mutating func padWeek() {
        while week.count < 7 { week.append(DayPlan(title: "휴식", exercises: [])) }
        if week.count > 7 { week = Array(week.prefix(7)) }
    }
}

// MARK: - 날짜 도우미

enum DayKey {
    static let weekdayNames = ["일", "월", "화", "수", "목", "금", "토"]

    static func weekDates(containing date: Date) -> [Date] {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: day) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -offset, to: day) ?? day
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    static func monthDates(containing date: Date) -> [Date] {
        let calendar = Calendar.current
        guard let month = calendar.dateInterval(of: .month, for: date),
              let range = calendar.range(of: .day, in: .month, for: date) else { return [] }
        let leading = (calendar.component(.weekday, from: month.start) + 5) % 7
        let count = ((leading + range.count + 6) / 7) * 7
        let start = calendar.date(byAdding: .day, value: -leading, to: month.start) ?? month.start
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

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
        scheduledPlans[DayKey.key(date)] ?? DayPlan(title: "휴식", exercises: [])
    }

    func doneSets(_ exercise: Exercise, on date: Date = Date()) -> Int {
        let key = DayKey.key(date)
        if let session = activeWorkout, session.day == key, session.plan.exercises.contains(where: { $0.id == exercise.id }) {
            return session.doneSets(exercise)
        }
        let raw = logs.first(where: { $0.day == key })?.doneSets[exercise.id.uuidString] ?? 0
        return min(max(raw, 0), max(exercise.sets, 0))
    }

    func progress(on date: Date = Date()) -> (done: Int, total: Int) {
        let p = activeWorkout.flatMap { $0.day == DayKey.key(date) ? $0.plan : nil } ?? plan(for: date)
        let done = p.exercises.reduce(0) { $0 + doneSets($1, on: date) }
        return (done, p.totalSets)
    }

    /// 다음에 할 세트 (휴식 타이머와 위젯에 표시)
    func nextUp(on date: Date = Date()) -> (title: String, info: String) {
        let p = activeWorkout.flatMap { $0.day == DayKey.key(date) ? $0.plan : nil } ?? plan(for: date)
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
        let currentPlan = activeWorkout.flatMap { $0.day == DayKey.key(date) ? $0.plan : nil } ?? plan(for: date)
        guard let exercise = currentPlan.exercises.first(where: { $0.id == exerciseID }) else { return }
        let key = DayKey.key(date)
        if !logs.contains(where: { $0.day == key }) {
            logs.append(DayLog(day: key))
        }
        guard let i = logs.firstIndex(where: { $0.day == key }) else { return }

        let current = doneSets(exercise, on: date)
        var next = current + delta
        if wrap && delta > 0 && current >= exercise.sets { next = 0 }
        logs[i].doneSets[exerciseID.uuidString] = min(max(next, 0), max(exercise.sets, 0))
        if activeWorkout?.day == key {
            activeWorkout?.completedSets[exerciseID.uuidString] = logs[i].doneSets[exerciseID.uuidString]
            if delta > 0, let session = activeWorkout, session.total > 0, session.done == session.total {
                finishWorkout()
            }
        }

        // 1년 넘은 기록은 정리
        if logs.count > 400 { logs.removeFirst(logs.count - 400) }
    }

    /// 오늘 이미 저장한 운동 일지가 있는지
    func hasSavedWorkout(on date: Date = Date()) -> Bool {
        let key = DayKey.key(date)
        return workouts.contains { $0.day == key }
    }

    /// 날짜가 지난 진행 중 운동을 정리. 완료 세트가 있으면 일지로 저장(끝난 시각은 모름), 없으면 버림.
    @discardableResult
    mutating func closeStaleWorkout(now: Date = Date()) -> Bool {
        guard let session = activeWorkout, session.day != DayKey.key(now) else { return false }
        if session.done > 0 && !workouts.contains(where: { $0.id == session.id }) {
            workouts.append(session)
        }
        activeWorkout = nil
        return true
    }

    @discardableResult
    mutating func startWorkout(at date: Date = Date()) -> Bool {
        closeStaleWorkout(now: date)
        guard activeWorkout == nil else { return false }
        let currentPlan = plan(for: date)
        guard !currentPlan.isRestDay else { return false }
        // 같은 날 이미 저장한 운동이 있으면 새 운동은 0세트부터 (이전 일지는 그대로 보존)
        let key = DayKey.key(date)
        if hasSavedWorkout(on: date), let i = logs.firstIndex(where: { $0.day == key }) {
            for exercise in currentPlan.exercises { logs[i].doneSets[exercise.id.uuidString] = 0 }
        }
        var session = WorkoutSession(startedAt: date, plan: currentPlan)
        for exercise in currentPlan.exercises {
            session.completedSets[exercise.id.uuidString] = doneSets(exercise, on: date)
        }
        activeWorkout = session
        if session.total > 0 && session.done == session.total { finishWorkout(at: date) }
        return true
    }

    @discardableResult
    mutating func finishWorkout(at date: Date = Date()) -> Bool {
        guard var session = activeWorkout, session.done > 0 else { return false }
        session.endedAt = max(date, session.startedAt)
        if let index = workouts.firstIndex(where: { $0.id == session.id }) {
            workouts[index] = session
        } else {
            workouts.append(session)
        }
        activeWorkout = nil
        return true
    }

    /// 위젯에서 세트를 체크할 때: 진행 중 운동이 없으면 자동으로 시작해서 운동 일지에 남게 함
    mutating func completeSetFromWidget(_ exerciseID: UUID, now: Date = Date()) {
        closeStaleWorkout(now: now)
        if activeWorkout == nil, !hasSavedWorkout(on: now) {
            let current = progress(on: now)
            if current.total > 0, current.done < current.total { startWorkout(at: now) }
        }
        changeSets(exerciseID, by: 1, wrap: true, on: now)
    }

    /// 선택한 주(월~일)의 계획을 이후 몇 주에 복사. 오늘 이후 날짜만 바꾸고, 지난 날짜·오늘은 건드리지 않음.
    mutating func repeatWeek(containing date: Date, weeks: Int, today: Date = Date()) {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: today)
        for week in 1...max(weeks, 1) {
            for day in DayKey.weekDates(containing: date) {
                guard let target = calendar.date(byAdding: .day, value: 7 * week, to: day),
                      calendar.startOfDay(for: target) > todayStart else { continue }
                let targetKey = DayKey.key(target)
                if var source = scheduledPlans[DayKey.key(day)] {
                    source.exercises = source.exercises.map { exercise in
                        var copy = exercise
                        copy.id = UUID()
                        return copy
                    }
                    scheduledPlans[targetKey] = source
                } else {
                    scheduledPlans.removeValue(forKey: targetKey)
                }
            }
        }
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
        func ex(_ name: String, _ sets: Int, _ detail: String) -> Exercise {
            Exercise(name: name, sets: sets, detail: detail)
        }
        func upper() -> DayPlan {
            DayPlan(title: "상체", exercises: [
                ex("푸쉬업", 5, "최대의 70%"),
                ex("풀업", 5, "최대의 70%"),
                ex("딥스", 3, "10회"),
                ex("플랭크", 3, "1분"),
            ])
        }
        func lower() -> DayPlan {
            DayPlan(title: "하체·코어", exercises: [
                ex("에어 스쿼트", 5, "20회"),
                ex("런지", 3, "다리당 12회"),
                ex("행잉 레그레이즈", 3, "12회"),
            ])
        }
        let cindy = DayPlan(title: "신디", exercises: [
            ex("워밍업", 1, "10분"),
            ex("신디", 1, "20분 AMRAP"),
            ex("스트레칭", 1, "10분"),
        ])
        let test = DayPlan(title: "기록 테스트", exercises: [
            ex("푸쉬업 최대", 1, "최대 반복"),
            ex("풀업 최대", 1, "최대 반복"),
        ])
        let rest = DayPlan(title: "휴식", exercises: [])
        return AppData(week: [rest, upper(), lower(), cindy, upper(), lower(), test])
    }
}

// MARK: - 일상: 할 일과 반복 습관

struct DailyItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case task, habit
        var title: String { self == .task ? "할 일" : "습관" }
    }
    enum RepeatRule: String, Codable, CaseIterable {
        case daily, weekdays, interval
        var title: String {
            switch self {
            case .daily: return "매일"
            case .weekdays: return "지정 요일"
            case .interval: return "며칠 간격"
            }
        }
    }
    var id = UUID()
    var title: String
    var note = ""
    var kind: Kind = .task
    var scheduledDate: Date?
    var startDate = Date()
    var repeatRule: RepeatRule = .daily
    var weekdays: [Int] = [1, 2, 3, 4, 5]
    var intervalDays = 2
    var skippedDays: Set<String> = []

    func occurs(on date: Date) -> Bool {
        let calendar = Calendar.current
        if kind == .task {
            return scheduledDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        }
        let start = calendar.startOfDay(for: startDate)
        let day = calendar.startOfDay(for: date)
        guard day >= start, !skippedDays.contains(DayKey.key(date)) else { return false }
        switch repeatRule {
        case .daily: return true
        case .weekdays: return weekdays.contains(DayKey.weekdayIndex(date))
        case .interval:
            let distance = calendar.dateComponents([.day], from: start, to: day).day ?? 0
            return distance % max(intervalDays, 1) == 0
        }
    }

    var scheduleDescription: String {
        if kind == .task {
            return scheduledDate?.formatted(.dateTime.month().day()) ?? "날짜 미정"
        }
        switch repeatRule {
        case .daily: return "매일"
        case .weekdays:
            return [1, 2, 3, 4, 5, 6, 0].filter { weekdays.contains($0) }
                .map { DayKey.weekdayNames[$0] }.joined(separator: " · ")
        case .interval: return "\(max(intervalDays, 1))일마다"
        }
    }
}

// 완료 당시 내용을 보존하여 계획의 수정·삭제와 독립적으로 표시.
struct DailyCompletion: Codable, Identifiable, Equatable {
    var id = UUID()
    var itemID: UUID
    var title: String
    var note: String
    var kind: DailyItem.Kind
    var day: String
    var completedAt: Date
}

extension AppData {
    func dailyItems(on date: Date, includeUndated: Bool = false) -> [DailyItem] {
        dailyItems.filter { $0.occurs(on: date) || (includeUndated && $0.kind == .task && $0.scheduledDate == nil) }
    }

    func isDailyComplete(_ item: DailyItem, on date: Date) -> Bool {
        dailyCompletions.contains {
            $0.itemID == item.id && (item.kind == .task || $0.day == DayKey.key(date))
        }
    }

    mutating func saveDailyItem(_ item: DailyItem) {
        guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var saved = item
        saved.title = saved.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = dailyItems.firstIndex(where: { $0.id == item.id }) { dailyItems[index] = saved }
        else { dailyItems.append(saved) }
    }

    mutating func toggleDailyCompletion(_ id: UUID, on date: Date, at timestamp: Date = Date()) {
        guard let item = dailyItems.first(where: { $0.id == id }),
              item.occurs(on: date) || (item.kind == .task && item.scheduledDate == nil) else { return }
        if isDailyComplete(item, on: date) {
            dailyCompletions.removeAll { $0.itemID == id && (item.kind == .task || $0.day == DayKey.key(date)) }
        } else {
            dailyCompletions.append(DailyCompletion(itemID: id, title: item.title, note: item.note,
                kind: item.kind, day: DayKey.key(date), completedAt: timestamp))
        }
    }

    mutating func skipDailyHabit(_ id: UUID, on date: Date) {
        guard let index = dailyItems.firstIndex(where: { $0.id == id && $0.kind == .habit }),
              !isDailyComplete(dailyItems[index], on: date) else { return }
        dailyItems[index].skippedDays.insert(DayKey.key(date))
    }
}