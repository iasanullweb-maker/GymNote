import Foundation

enum RestDuration {
    static func text(seconds: Int) -> String {
        let seconds = max(seconds, 0)
        return seconds < 60 ? "\(seconds)초" : "\(seconds / 60)분 \(seconds % 60)초"
    }

    static func remaining(until end: Date, at now: Date) -> Int {
        max(0, Int(ceil(end.timeIntervalSince(now))))
    }
}

// MARK: - 루틴

struct Exercise: Codable, Identifiable, Hashable {
    var hasPercentageTarget: Bool { detail.contains("%") || detail.contains("％") }

    /// Only an unambiguous repetition target supplies the default; time/ranges stay free-form.
    var plannedReps: Int? {
        guard detail.range(of: "[0-9]\\s*[-~–]\\s*[0-9]", options: .regularExpression) == nil,
              let regex = try? NSRegularExpression(pattern: "(?<![0-9.−-])([0-9]+)\\s*회") else { return nil }
        let matches = regex.matches(in: detail, range: NSRange(detail.startIndex..., in: detail))
        guard matches.count == 1, let range = Range(matches[0].range(at: 1), in: detail),
              let value = Int(detail[range]), (0...9999).contains(value) else { return nil }
        return value
    }
    var id: UUID = UUID()
    var name: String
    var sets: Int
    var detail: String      // 예: "10회", "1분"
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

// MARK: - 실행 탭 순서

/// 실행 탭 목록에서 한 운동을 옮길 위치 (접근성 동작용)
enum ExecutionMove: CaseIterable, Equatable {
    case up, down, top, bottom
}

extension AppData {
    /// 실행 탭에 보이는 계획. 진행 중 운동이 있으면 시작한 날짜와 관계없이 그 운동의 계획.
    private func executionPlan(on date: Date) -> DayPlan {
        activeWorkout?.plan ?? plan(for: date)
    }

    /// 진행 중 운동은 세션 기록으로, 아니면 그날 기록으로 판단한다(자정 이후에도 시작한 운동 기준).
    func isExecutionFinished(_ exercise: Exercise, on date: Date = Date()) -> Bool {
        let done = activeWorkout.map { $0.doneSets(exercise) } ?? doneSets(exercise, on: date)
        return done >= max(exercise.sets, 0)
    }

    /// 완료한 운동은 아래에 모아 보여 준다. 저장된 순서는 바꾸지 않으므로
    /// 완료를 취소하면 사용자가 정한 원래 위치로 돌아간다.
    func executionExercises(on date: Date = Date()) -> [Exercise] {
        let exercises = executionPlan(on: date).exercises
        let unfinished = exercises.filter { !isExecutionFinished($0, on: date) }
        let finished = exercises.filter { isExecutionFinished($0, on: date) }
        return unfinished + finished
    }

    /// 화면 목록(`executionExercises`) 기준으로 운동을 옮긴다. `List.onMove`와 같은 규칙으로
    /// `destination`은 옮기기 전 목록 기준 삽입 위치(0...count)라 아래로·맨 끝으로도 옮길 수 있다.
    ///
    /// - 미완료/완료 묶음 안에서만 순서가 바뀐다. 경계를 넘겨 놓으면 같은 묶음의 끝(또는 앞)에 놓인다.
    /// - 다른 묶음의 저장 위치는 그대로라 완료를 취소하면 원래 자리로 돌아간다.
    /// - 운동 ID·세트 수·실제 횟수·무게·저장된 일지는 바꾸지 않는다. 순서만 바뀐다.
    @discardableResult
    mutating func moveExecutionExercises(fromOffsets source: IndexSet, toOffset destination: Int,
                                         on date: Date = Date()) -> Bool {
        let display = executionExercises(on: date)
        guard !source.isEmpty, source.allSatisfy({ display.indices.contains($0) }),
              (0...display.count).contains(destination) else { return false }
        // Array.move(fromOffsets:toOffset:)와 같은 동작. 위젯·검사 스크립트는 SwiftUI 없이 컴파일하므로 직접 구현.
        let moving = source.map { display[$0] }
        var reordered = display.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        reordered.insert(contentsOf: moving, at: min(max(insertAt, 0), reordered.count))
        return applyExecutionOrder(reordered.map(\.id), on: date)
    }

    /// 접근성 동작(위로/아래로/맨 위로/맨 아래로). 같은 완료 묶음 안에서 움직인다.
    @discardableResult
    mutating func moveExecutionExercise(_ id: UUID, _ move: ExecutionMove, on date: Date = Date()) -> Bool {
        guard let target = executionMoveTarget(id, move, on: date) else { return false }
        return moveExecutionExercises(fromOffsets: IndexSet(integer: target.index), toOffset: target.destination, on: date)
    }

    /// 옮길 수 있는 방향만 접근성 동작으로 보여 주기 위한 확인.
    func canMoveExecutionExercise(_ id: UUID, _ move: ExecutionMove, on date: Date = Date()) -> Bool {
        executionMoveTarget(id, move, on: date) != nil
    }

    private func executionMoveTarget(_ id: UUID, _ move: ExecutionMove, on date: Date) -> (index: Int, destination: Int)? {
        let display = executionExercises(on: date)
        guard let index = display.firstIndex(where: { $0.id == id }) else { return nil }
        let finished = isExecutionFinished(display[index], on: date)
        let group = display.indices.filter { isExecutionFinished(display[$0], on: date) == finished }
        guard let first = group.first, let last = group.last else { return nil }
        let destination: Int
        switch move {
        case .up: destination = index - 1
        case .down: destination = index + 2
        case .top: destination = first
        case .bottom: destination = last + 1
        }
        guard destination >= first, destination <= last + 1, destination != index, destination != index + 1
        else { return nil }
        return (index, destination)
    }

    /// 화면 순서를 저장 순서에 반영한다. 각 묶음은 자기 묶음이 차지하던 자리 안에서만 재배치한다.
    private mutating func applyExecutionOrder(_ displayOrder: [UUID], on date: Date) -> Bool {
        let current = executionPlan(on: date)
        let currentIDs = current.exercises.map(\.id)
        // 같은 ID가 두 번 들어간 예전 계획은 어느 쪽을 옮길지 알 수 없으므로 건드리지 않는다.
        guard Set(currentIDs).count == currentIDs.count, displayOrder.count == currentIDs.count,
              Set(displayOrder) == Set(currentIDs) else { return false }
        let finishedIDs = Set(current.exercises.filter { isExecutionFinished($0, on: date) }.map(\.id))
        var unfinishedQueue = displayOrder.filter { !finishedIDs.contains($0) }[...]
        var finishedQueue = displayOrder.filter { finishedIDs.contains($0) }[...]
        let byID = Dictionary(current.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var exercises: [Exercise] = []
        for slot in current.exercises {
            let next = finishedIDs.contains(slot.id) ? finishedQueue.popFirst() : unfinishedQueue.popFirst()
            guard let id = next, let exercise = byID[id] else { return false }
            exercises.append(exercise)
        }
        guard exercises.map(\.id) != currentIDs else { return false }

        if var session = activeWorkout {
            session.plan.exercises = exercises
            activeWorkout = session
            // 같은 날 일정이 같은 운동들로 이뤄져 있으면 순서를 맞춰 '새 운동 시작'에도 유지한다.
            // 일정 쪽 운동 내용(세트·횟수)은 그대로 둔다.
            if var scheduled = scheduledPlans[session.day] {
                let scheduledIDs = scheduled.exercises.map(\.id)
                if scheduledIDs.count == exercises.count, Set(scheduledIDs) == Set(exercises.map(\.id)),
                   Set(scheduledIDs).count == scheduledIDs.count {
                    let scheduledByID = Dictionary(scheduled.exercises.map { ($0.id, $0) },
                                                   uniquingKeysWith: { first, _ in first })
                    scheduled.exercises = exercises.compactMap { scheduledByID[$0.id] }
                    scheduledPlans[session.day] = scheduled
                }
            }
        } else {
            var updated = current
            updated.exercises = exercises
            scheduledPlans[DayKey.key(date)] = updated
        }
        return true
    }
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

    /// 횟수와 완료 라운드는 정수로만 기록한다. 무게·시간의 소수는 유지한다.
    var requiresWholeValue: Bool {
        let normalizedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        return style == .rounds || normalizedUnit == "회" || normalizedUnit.isEmpty
    }

    func acceptsValue(_ value: Double) -> Bool {
        value.isFinite && (!requiresWholeValue || value.rounded(.towardZero) == value)
    }

    func acceptsCompetitiveRecord(_ entry: RecordEntry) -> Bool {
        guard acceptsValue(entry.value), (0...100_000).contains(entry.value), entry.extraReps >= 0 else { return false }
        return style == .rounds ? entry.extraReps < repsPerRound : entry.extraReps == 0
    }

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
    // Missing entries mean the actual count was not recorded (older journals).
    var actualReps: [String: [Int?]] = [:]
    var actualWeights: [String: [Double?]] = [:] // 세트별 kg. 이전 일지는 미기록.

    var day: String { DayKey.key(startedAt) }
    var done: Int { plan.exercises.reduce(0) { $0 + doneSets($1) } }
    var total: Int { plan.totalSets }
    func doneSets(_ exercise: Exercise) -> Int {
        min(max(completedSets[exercise.id.uuidString] ?? 0, 0), max(exercise.sets, 0))
    }

    func repetitions(_ exercise: Exercise, set index: Int) -> Int? {
        guard index >= 0, index < doneSets(exercise),
              let values = actualReps[exercise.id.uuidString], index < values.count else { return nil }
        return values[index]
    }
}

extension WorkoutSession {
    private enum CodingKeys: String, CodingKey { case id, startedAt, endedAt, plan, completedSets, actualReps, actualWeights }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        plan = try c.decode(DayPlan.self, forKey: .plan)
        completedSets = try c.decodeIfPresent([String: Int].self, forKey: .completedSets) ?? [:]
        actualReps = try c.decodeIfPresent([String: [Int?]].self, forKey: .actualReps) ?? [:]
        actualWeights = try c.decodeIfPresent([String: [Double?]].self, forKey: .actualWeights) ?? [:]
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
    var dailyReminders = DailyReminderSettings()

    enum CodingKeys: String, CodingKey {
        case week, recordTypes, records, logs, defaultRest, restSound, restStep, scheduledPlans, exerciseLibrary, activeWorkout, workouts, dailyItems, dailyCompletions, dailyReminders
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
        normalizePercentageTargets()
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
        dailyReminders = try c.decodeIfPresent(DailyReminderSettings.self, forKey: .dailyReminders) ?? DailyReminderSettings()
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
        normalizePercentageTargets()
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

    /// key(_:)의 역변환. 그날 정오를 돌려준다(시간대·일광 절약 경계에서도 같은 날짜 유지).
    static func date(fromKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
        return date.flatMap { self.key($0) == key ? $0 : nil }
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
    /// 비율로 저장된 계획은 사용자 요청대로 10회로 통일한다. 과거 일지·실제 횟수는 보존한다.
    mutating func normalizePercentageTargets() {
        func normalized(_ exercise: Exercise) -> Exercise {
            var result = exercise
            if result.hasPercentageTarget { result.detail = "10회" }
            return result
        }
        func normalizedPlan(_ plan: DayPlan) -> DayPlan {
            var result = plan
            result.exercises = result.exercises.map(normalized)
            return result
        }
        week = week.map(normalizedPlan)
        scheduledPlans = scheduledPlans.mapValues(normalizedPlan)
        exerciseLibrary = exerciseLibrary.map(normalized)
        if var workout = activeWorkout {
            workout.plan = normalizedPlan(workout.plan)
            activeWorkout = workout
        }
    }

    /// 시작 날짜 기준. 자정을 넘겨 종료한 운동도 시작한 날에 표시한다.
    func workouts(on date: Date) -> [WorkoutSession] {
        let day = DayKey.key(date)
        return workouts.filter { $0.day == day }.sorted { $0.startedAt > $1.startedAt }
    }

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
    mutating func changeSets(_ exerciseID: UUID, by delta: Int, wrap: Bool = false, on date: Date = Date(), actualReps: Int? = nil, at completedAt: Date = Date()) {
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
            let count = logs[i].doneSets[exerciseID.uuidString] ?? 0
            var values = activeWorkout?.actualReps[exerciseID.uuidString] ?? []
            values = Array(values.prefix(count))
            while values.count < current && values.count < count { values.append(nil) }
            while values.count < count {
                values.append((actualReps ?? exercise.plannedReps).map { min(max($0, 0), 9999) })
            }
            activeWorkout?.actualReps[exerciseID.uuidString] = values
            if delta > 0, let session = activeWorkout, session.total > 0, session.done == session.total {
                finishWorkout(at: completedAt)
            }
        }

        // 1년 넘은 기록은 정리
        if logs.count > 400 { logs.removeFirst(logs.count - 400) }
    }

    mutating func updateRepetitions(sessionID: UUID, exerciseID: UUID, set index: Int, value: Int) {
        func updated(_ session: WorkoutSession) -> WorkoutSession {
            guard let exercise = session.plan.exercises.first(where: { $0.id == exerciseID }),
                  index >= 0, index < session.doneSets(exercise) else { return session }
            var copy = session
            var values = copy.actualReps[exerciseID.uuidString] ?? []
            while values.count < copy.doneSets(exercise) { values.append(nil) }
            values[index] = min(max(value, 0), 9999)
            copy.actualReps[exerciseID.uuidString] = values
            return copy
        }
        if let session = activeWorkout, session.id == sessionID { activeWorkout = updated(session) }
        if let i = workouts.firstIndex(where: { $0.id == sessionID }) { workouts[i] = updated(workouts[i]) }
    }

    /// 오늘 이미 저장한 운동 일지가 있는지
    func hasSavedWorkout(on date: Date = Date()) -> Bool {
        let key = DayKey.key(date)
        return workouts.contains { $0.day == key }
    }

    @discardableResult
    mutating func startWorkout(at date: Date = Date()) -> Bool {
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
        if activeWorkout == nil, !hasSavedWorkout(on: now) {
            let current = progress(on: now)
            if current.total > 0, current.done < current.total { startWorkout(at: now) }
        }
        // 자정 이후에도 시작한 날의 진행 중 운동을 체크한다.
        let workoutDate = activeWorkout?.startedAt ?? now
        changeSets(exerciseID, by: 1, wrap: true, on: workoutDate, at: now)
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
                ex("푸쉬업", 5, "10회"),
                ex("풀업", 5, "10회"),
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

// MARK: - 일상: 한 번 하는 일과 반복하는 일
// 화면에서는 '반복' 설정 하나로 다룬다. 저장 형식은 예전 버전과 호환되도록 유지:
// kind == .task → 반복 안 함(한 번), kind == .habit → 반복 (repeatRule 사용).

/// 알림 시각(시·분). 날짜와 분리해 반복 일정의 매 회차에 적용한다.
struct ReminderTime: Codable, Hashable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: parts.hour ?? 9, minute: parts.minute ?? 0)
    }

    /// 해당 날짜의 이 시각. 일광 절약 시간 등으로 존재하지 않는 시각이면 nil.
    func date(on day: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    /// 편집기의 DatePicker에 쓰는 오늘 날짜 기준 시각.
    var pickerDate: Date { date(on: Date()) ?? Date() }
    var label: String { String(format: "%02d:%02d", hour, minute) }
}

/// 일상 알림 전체 설정. 계정과 함께 동기화되고, 예약은 기기마다 따로 한다.
struct DailyReminderSettings: Codable, Equatable {
    var enabled = true
    var sound = true
    var morningSummary: ReminderTime?   // 아침 요약 (기본 꺼짐)
    var eveningCheck: ReminderTime?     // 저녁 미완료 확인 (기본 꺼짐)

    init() {}

    private enum CodingKeys: String, CodingKey { case enabled, sound, morningSummary, eveningCheck }

    // 필드가 늘어나도 예전 저장값을 읽을 수 있게 하나씩 꺼냄
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        sound = try c.decodeIfPresent(Bool.self, forKey: .sound) ?? true
        morningSummary = try c.decodeIfPresent(ReminderTime.self, forKey: .morningSummary)
        eveningCheck = try c.decodeIfPresent(ReminderTime.self, forKey: .eveningCheck)
    }
}

struct DailyItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case task, habit
        var title: String { self == .task ? "한 번" : "반복" }
    }
    /// 편집 화면의 '반복' 선택지. 안 함 = 한 번 하는 일.
    enum RepeatChoice: String, CaseIterable, Identifiable {
        case none, daily, weekdays, interval
        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: return "안 함"
            case .daily: return "매일"
            case .weekdays: return "요일 지정"
            case .interval: return "며칠 간격"
            }
        }
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
    var reminderTime: ReminderTime?

    var isRepeating: Bool { kind == .habit }
    var isUndated: Bool { kind == .task && scheduledDate == nil }

    var repeatChoice: RepeatChoice {
        get {
            guard isRepeating else { return .none }
            switch repeatRule {
            case .daily: return .daily
            case .weekdays: return .weekdays
            case .interval: return .interval
            }
        }
        set {
            switch newValue {
            case .none: kind = .task
            case .daily: kind = .habit; repeatRule = .daily
            case .weekdays: kind = .habit; repeatRule = .weekdays
            case .interval: kind = .habit; repeatRule = .interval
            }
        }
    }

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

    /// 편집 저장. 반복하던 항목을 '안 함'으로 바꾸면 예전 날짜별 완료 기록 때문에
    /// 이미 끝난 것으로 보이지 않도록 새 항목으로 저장한다(기존 완료 기록은 기록 화면에 그대로 남음).
    mutating func saveDailyItemEditing(_ item: DailyItem) {
        var saved = item
        if !saved.isRepeating { saved.skippedDays = [] }
        if saved.isUndated { saved.reminderTime = nil }
        if let previous = dailyItems.first(where: { $0.id == item.id }), previous.isRepeating, !saved.isRepeating {
            guard !saved.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            dailyItems.removeAll { $0.id == previous.id }
            saved.id = UUID()
        }
        saveDailyItem(saved)
    }

    /// 알림의 '완료' 버튼처럼 되돌리기 없이 완료만 기록한다. 이미 완료됐거나 예정이 아니면 아무것도 하지 않는다.
    @discardableResult
    mutating func markDailyComplete(_ id: UUID, on date: Date, at timestamp: Date = Date()) -> Bool {
        guard let item = dailyItems.first(where: { $0.id == id }),
              item.occurs(on: date) || item.isUndated, !isDailyComplete(item, on: date) else { return false }
        toggleDailyCompletion(id, on: date, at: timestamp)
        return true
    }

    mutating func skipDailyHabit(_ id: UUID, on date: Date) {
        guard let index = dailyItems.firstIndex(where: { $0.id == id && $0.kind == .habit }),
              !isDailyComplete(dailyItems[index], on: date) else { return }
        dailyItems[index].skippedDays.insert(DayKey.key(date))
    }
}
