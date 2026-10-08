import Foundation

@main
struct ManualWorkoutChecks {
    static func main() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let date = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let exercise = Exercise(name: "스쿼트", sets: 3, detail: "10회")
        var draft = ManualWorkoutDraft(date: date)
        assert(draft.session() == nil, "빈 일지는 저장하지 않음")
        draft.append(exercise)
        draft.moves[0].sets[0].reps = "8"
        draft.moves[0].sets[0].weight = "20,5"
        let session = draft.session()!
        let move = session.plan.exercises[0]
        assert(move.id != exercise.id, "루틴 ID와 분리")
        assert(session.done == 3 && session.total == 3 && session.day == DayKey.key(date))
        assert(session.repetitions(move, set: 0) == 8)
        assert(session.repetitions(move, set: 1) == 10)
        assert(session.actualWeights[move.id.uuidString]![0] == 20.5)
        assert(session.endedAt == nil, "운동 시간을 임의로 만들지 않음")
        let restoredDraft = try decoder.decode(ManualWorkoutDraft.self, from: encoder.encode(draft))
        assert(restoredDraft == draft)
        assert(ManualWorkoutDraft.storageKey(userID: UUID()) != ManualWorkoutDraft.storageKey(userID: nil))

        var data = AppData.sample
        data.scheduledPlans[DayKey.key()] = DayPlan(title: "진행 중", exercises: [exercise])
        data.startWorkout()
        let active = data.activeWorkout
        assert(active != nil)
        let logs = data.logs
        let plans = data.scheduledPlans
        let previous = data
        data.workouts.append(session)
        assert(data.activeWorkout == active && data.logs == logs && data.scheduledPlans == plans)
        let reloaded = try decoder.decode(AppData.self, from: encoder.encode(data))
        assert(reloaded.workouts == data.workouts, "세트별 무게/횟수 저장 왕복")
        var concurrent = previous
        concurrent.records.append(RecordEntry(typeID: "pushup", date: Date(), value: 25))
        let merged = concurrent.applyingEdits(from: previous, to: data)
        assert(merged.workouts.contains(session) && merged.records == concurrent.records)

        var legacy = try JSONSerialization.jsonObject(with: encoder.encode(session)) as! [String: Any]
        legacy.removeValue(forKey: "actualWeights")
        let old = try decoder.decode(WorkoutSession.self, from: JSONSerialization.data(withJSONObject: legacy))
        assert(old.actualWeights.isEmpty && old.actualReps == session.actualReps)
        var copy = ManualWorkoutDraft()
        copy.append(move, session: session)
        assert(copy.moves[0].id != move.id && copy.moves[0].sets[0].reps == "8")
        assert(copy.moves[0].sets[0].weight == "20.5")
        draft.moves[0].sets[0].weight = "nan"
        assert(draft.session() == nil)
        draft.moves[0].sets[0].weight = "-1"
        assert(draft.session() == nil)
        draft.moves[0].sets[0].weight = ""
        draft.moves[0].sets[0].reps = "10000"
        assert(draft.session() == nil)
        draft.moves[0].sets[0].reps = ""
        draft.moves[0].detail = "1분"
        assert(draft.session() != nil, "시간 운동은 횟수 미기록 허용")
        draft.date = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        assert(draft.session() == nil, "미래 운동 저장 방지")
        print("Manual workout checks passed")
    }
}
