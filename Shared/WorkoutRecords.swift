import Foundation

// MARK: - 운동 일지로 자동 계산하는 최고기록
// 저장하지 않고 일지(마친 운동)에서 매번 계산한다. 그래서 일지를 고치거나 지우면 자동으로 다시 계산되고,
// 저장 형식이 바뀌지 않아 예전 앱·다른 기기와 동기화에도 영향이 없다.
// 계획 횟수는 쓰지 않고, 세트마다 실제로 기록한 횟수(actualReps)만 사용한다.

struct AutoRecord: Equatable {
    var value: Int
    var date: Date
}

/// 한 운동(이름 기준)의 자동 최고기록
struct ExerciseRecords: Equatable, Identifiable {
    var key: String
    var name: String          // 가장 최근 일지에 쓴 이름
    var bestSet: AutoRecord?  // 한 세트 최대 횟수
    var bestDay: AutoRecord?  // 같은 날 모든 운동의 합계 최대
    var id: String { key }
}

/// 위젯·요약에 쓰는 한 줄
struct RecordSummary: Equatable, Identifiable {
    var id: String
    var name: String
    var setText: String       // 한 세트(또는 수동 기록) 최고
    var dayText: String?      // 하루 총량 최고 (자동 기록이 있을 때만)
}

extension AppData {
    /// 같은 운동 판단 기준: 앞뒤·중간 공백과 대소문자를 무시한 이름. ("에어 스쿼트" = "에어스쿼트")
    static func exerciseKey(_ name: String) -> String {
        name.lowercased().filter { !$0.isWhitespace }
    }

    /// 마친 운동 일지에서 계산한 운동별 최고기록. 같은 값이면 먼저 달성한 날짜를 유지한다.
    func exerciseRecords() -> [String: ExerciseRecords] {
        var result: [String: ExerciseRecords] = [:]
        var dayTotals: [String: [String: (value: Int, date: Date)]] = [:] // key → day → 합계
        for session in workouts.sorted(by: { $0.startedAt < $1.startedAt }) {
            for exercise in session.plan.exercises {
                let key = Self.exerciseKey(exercise.name)
                guard !key.isEmpty else { continue }
                let values = (0..<session.doneSets(exercise)).compactMap { session.repetitions(exercise, set: $0) }
                guard let best = values.max(), best > 0 else { continue }
                var record = result[key] ?? ExerciseRecords(key: key, name: exercise.name)
                record.name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if best > (record.bestSet?.value ?? 0) { record.bestSet = AutoRecord(value: best, date: session.startedAt) }
                result[key] = record
                let previous = dayTotals[key, default: [:]][session.day]
                dayTotals[key, default: [:]][session.day] =
                    ((previous?.value ?? 0) + values.reduce(0, +), previous?.date ?? session.startedAt)
            }
        }
        for (key, days) in dayTotals {
            let best = days.values.sorted { $0.date < $1.date }.reduce(nil as AutoRecord?) { current, day in
                day.value > (current?.value ?? 0) ? AutoRecord(value: day.value, date: day.date) : current
            }
            result[key]?.bestDay = best
        }
        return result
    }

    /// 자동 기록을 합칠 수 있는 수동 종목: 숫자 하나·'회' 단위·높을수록 좋은 종목.
    static func acceptsWorkoutRepetitions(_ type: RecordType) -> Bool {
        type.style == .count && !type.lowerIsBetter && (type.unit == "회" || type.unit.isEmpty)
    }

    func linkedRecordType(for key: String) -> RecordType? {
        recordTypes.first { Self.acceptsWorkoutRepetitions($0) && Self.exerciseKey($0.name) == key }
    }

    func exerciseRecords(for type: RecordType, in all: [String: ExerciseRecords]? = nil) -> ExerciseRecords? {
        guard Self.acceptsWorkoutRepetitions(type) else { return nil }
        return (all ?? exerciseRecords())[Self.exerciseKey(type.name)]
    }

    /// 수동 기록과 운동 일지 중 더 높은 한 세트 기록. 같으면 먼저 달성한 쪽.
    func combinedBestSet(for type: RecordType, auto: ExerciseRecords?) -> (value: Double, date: Date, fromJournal: Bool)? {
        let manual = best(type).map { (value: $0.value, date: $0.date, fromJournal: false) }
        let journal = auto?.bestSet.map { (value: Double($0.value), date: $0.date, fromJournal: true) }
        switch (manual, journal) {
        case let (m?, j?):
            if j.value > m.value || (j.value == m.value && j.date < m.date) { return j }
            return m
        case let (m?, nil): return m
        case let (nil, j?): return j
        default: return nil
        }
    }

    /// 수동 종목과 이름이 같지 않은 운동의 자동 기록 (기록 화면 아래 '운동 일지 자동 기록')
    func unlinkedExerciseRecords(_ all: [String: ExerciseRecords]? = nil) -> [ExerciseRecords] {
        (all ?? exerciseRecords()).values
            .filter { linkedRecordType(for: $0.key) == nil }
            .sorted { ($0.bestSet?.date ?? .distantPast) > ($1.bestSet?.date ?? .distantPast) }
    }

    /// 위젯: 그날 계획한 운동의 '세트 · 하루' 최고기록. 운동이 없는 날은 기록 목록 위 종목.
    func recordSummaries(on date: Date = Date(), limit: Int = 3) -> [RecordSummary] {
        let all = exerciseRecords()
        var seen = Set<String>()
        var rows: [RecordSummary] = []
        for exercise in plan(for: date).exercises {
            let key = Self.exerciseKey(exercise.name)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            let auto = all[key]
            let set: String
            if let type = linkedRecordType(for: key), let combined = combinedBestSet(for: type, auto: auto) {
                set = RecordType.number(combined.value)
            } else {
                set = auto?.bestSet.map { "\($0.value)" } ?? "–"
            }
            rows.append(RecordSummary(id: key, name: exercise.name, setText: set,
                                      dayText: auto?.bestDay.map { "\($0.value)" }))
            if rows.count == limit { break }
        }
        if !rows.isEmpty { return rows }
        return widgetTypes(limit).map { type in
            let auto = exerciseRecords(for: type, in: all)
            let set: String
            if let combined = combinedBestSet(for: type, auto: auto), combined.fromJournal { set = RecordType.number(combined.value) }
            else { set = self.best(type).map { type.shortDisplay($0) } ?? "–" }
            return RecordSummary(id: type.id, name: type.name, setText: set, dayText: auto?.bestDay.map { "\($0.value)" })
        }
    }

    /// 운동을 마친 뒤 이전보다 좋아진 기록 문구. 처음 생긴 기록은 알리지 않는다(비교 대상이 있을 때만).
    func recordImprovements(since before: [String: ExerciseRecords]) -> [String] {
        let after = exerciseRecords()
        var messages: [String] = []
        for key in after.keys.sorted() {
            guard let now = after[key] else { continue }
            let previous = before[key]
            let manualBest = linkedRecordType(for: key).flatMap { best($0) }?.value
            let previousSet = max(Double(previous?.bestSet?.value ?? 0), manualBest ?? 0)
            if let set = now.bestSet, previousSet > 0, Double(set.value) > previousSet {
                messages.append("\(now.name) 한 세트 \(set.value)회")
            }
            if let day = now.bestDay, let old = previous?.bestDay, day.value > old.value {
                messages.append("\(now.name) 하루 총량 \(day.value)회")
            }
        }
        return messages
    }
}
