import Foundation

struct ManualWorkoutDraft: Codable, Equatable {
    static func storageKey(userID: UUID?) -> String {
        "manual-workout-draft-\(userID?.uuidString ?? "guest")"
    }
    struct SetEntry: Codable, Identifiable, Equatable {
        var id = UUID()
        var reps = ""
        var weight = ""
        var repetitionValue: Int? { Int(reps.trimmingCharacters(in: .whitespaces)) }
        var weightValue: Double? { Double(weight.replacingOccurrences(of: ",", with: ".")) }
        var isValid: Bool {
            (reps.isEmpty || repetitionValue.map { (0...9999).contains($0) } == true)
                && (weight.isEmpty || weightValue.map { $0.isFinite && (0...9999).contains($0) } == true)
        }
    }
    struct Move: Codable, Identifiable, Equatable {
        var id = UUID()
        var name = ""
        var detail = ""
        var sets = [SetEntry()]
        var isValid: Bool {
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !sets.isEmpty && sets.count <= 100 && sets.allSatisfy {
                    $0.isValid && (!$0.reps.isEmpty || !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
        }
    }
    var date = Date()
    var title = "지난 운동"
    var moves: [Move] = []

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !moves.isEmpty && moves.allSatisfy(\.isValid)
            && Calendar.current.startOfDay(for: date) <= Calendar.current.startOfDay(for: Date())
    }

    mutating func append(_ exercise: Exercise, session: WorkoutSession? = nil) {
        let count = session.map { $0.doneSets(exercise) } ?? exercise.sets
        guard count > 0 else { return }
        let entries = (0..<min(count, 100)).map { index in
            let reps = session != nil ? session?.repetitions(exercise, set: index) : exercise.plannedReps
            let weights = session?.actualWeights[exercise.id.uuidString] ?? []
            let weight = index < weights.count ? weights[index] : nil
            return SetEntry(reps: reps.map { String($0) } ?? "", weight: weight.map { RecordType.number($0) } ?? "")
        }
        moves.append(Move(name: exercise.name, detail: exercise.detail, sets: entries))
    }

    func session() -> WorkoutSession? {
        guard isValid else { return nil }
        // Imported exercises get new IDs, keeping today's plan/logs and active workout independent.
        let exercises = moves.map {
            Exercise(id: $0.id, name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                     sets: $0.sets.count, detail: $0.detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var result = WorkoutSession(startedAt: date,
                                    plan: DayPlan(title: title.trimmingCharacters(in: .whitespacesAndNewlines), exercises: exercises))
        // No elapsed time is invented for a retrospective entry.
        for (move, exercise) in zip(moves, exercises) {
            let key = exercise.id.uuidString
            result.completedSets[key] = move.sets.count
            result.actualReps[key] = move.sets.map(\.repetitionValue)
            result.actualWeights[key] = move.sets.map(\.weightValue)
        }
        return result
    }
}
