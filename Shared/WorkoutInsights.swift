import Foundation

/// A saved session is the source of truth. Missing actual values stay missing.
struct PreviousExercise: Equatable {
    let session: WorkoutSession
    let exercise: Exercise

    var repetitions: [Int?] {
        (0..<session.doneSets(exercise)).map { session.repetitions(exercise, set: $0) }
    }

    var text: String {
        (0..<session.doneSets(exercise)).map { index in
            let reps = session.repetitions(exercise, set: index).map { "\($0)회" } ?? "횟수 미기록"
            let weights = session.actualWeights[exercise.id.uuidString] ?? []
            let weight = index < weights.count ? weights[index] : nil
            return reps + (weight.map { " · \(RecordType.number($0))kg" } ?? "")
        }.joined(separator: " / ")
    }

    func repetition(at index: Int) -> Int? {
        guard repetitions.indices.contains(index), let value = repetitions[index],
              (0...9999).contains(value) else { return nil }
        return value
    }
}

extension AppData {
    /// Match names across copied routines, but never choose the current session or future data.
    func previousExercise(named name: String, before date: Date, excluding sessionID: UUID? = nil) -> PreviousExercise? {
        let key = Self.exerciseKey(name)
        guard !key.isEmpty else { return nil }
        for session in workouts.filter({ $0.id != sessionID && $0.startedAt < date })
            .sorted(by: { $0.startedAt > $1.startedAt }) {
            // Repeated entries for the same name are ambiguous; do not copy the wrong set.
            let matches = session.plan.exercises.filter {
                Self.exerciseKey($0.name) == key && session.doneSets($0) > 0
            }
            if matches.count == 1 { return PreviousExercise(session: session, exercise: matches[0]) }
        }
        return nil
    }

    func workoutSummary(_ session: WorkoutSession) -> WorkoutSummary {
        let values = session.plan.exercises.flatMap { exercise in
            (0..<session.doneSets(exercise)).map { session.repetitions(exercise, set: $0) }
        }
        let known = values.compactMap { $0 }
        let signature = session.comparisonSignature
        let previous = signature.flatMap { signature in
            workouts.filter { $0.id != session.id && $0.startedAt < session.startedAt && $0.comparisonSignature == signature }
                .max { $0.startedAt < $1.startedAt }
        }
        let previousTotal = previous.map { previous in
            previous.plan.exercises.reduce(0) { total, exercise in
                total + (0..<previous.doneSets(exercise)).compactMap { previous.repetitions(exercise, set: $0) }.reduce(0, +)
            }
        }
        var before = self
        before.workouts.removeAll { $0.id == session.id || $0.startedAt >= session.startedAt }
        var throughSession = before
        throughSession.workouts.append(session)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: session.startedAt)
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let days = Set(workouts.filter { $0.done > 0 && $0.startedAt >= start && $0.startedAt < end }.map(\.day))
        return WorkoutSummary(session: session, recordedReps: known.reduce(0, +), recordedSets: known.count,
                              previousDate: previous?.startedAt, repetitionChange: previousTotal.map { known.reduce(0, +) - $0 },
                              workoutDays: days.count, improvements: throughSession.recordImprovements(since: before.exerciseRecords()))
    }
}

struct WorkoutSummary {
    let session: WorkoutSession
    let recordedReps: Int
    let recordedSets: Int
    let previousDate: Date?
    let repetitionChange: Int?
    let workoutDays: Int
    let improvements: [String]

    var duration: Int? { session.endedAt.map { max(0, Int($0.timeIntervalSince(session.startedAt))) } }
}

private extension WorkoutSession {
    /// Only compare fully completed sessions with all actual reps and identical loads/set counts.
    /// A missing load is distinct from a measured zero. Partial/time workouts get no growth claim.
    var comparisonSignature: [String]? {
        guard total > 0, done == total else { return nil }
        var keys = Set<String>()
        var signatures: [String] = []
        for exercise in plan.exercises {
            let key = AppData.exerciseKey(exercise.name)
            guard !key.isEmpty, exercise.sets > 0, keys.insert(key).inserted,
                  (0..<doneSets(exercise)).allSatisfy({ repetitions(exercise, set: $0) != nil }) else { return nil }
            let weights = actualWeights[exercise.id.uuidString] ?? []
            let loads = (0..<doneSets(exercise)).map { index -> String in
                let weight = index < weights.count ? weights[index] : nil
                return weight.map { String($0) } ?? "missing"
            }.joined(separator: ",")
            signatures.append("\(key)|\(exercise.sets)|\(loads)")
        }
        return signatures.sorted()
    }
}
