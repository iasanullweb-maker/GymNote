import Foundation

/// Server-owned definitions. IDs never overlap with the old, user-owned record types.
struct CatalogRecordType: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var unit: String
    var style: RecordType.Style
    var repsPerRound: Int
    var lowerIsBetter: Bool
    var hint: String
    var active: Bool
    var position: Int
    var revision: Int64

    var recordType: RecordType {
        RecordType(id: id, name: name, unit: unit, style: style, repsPerRound: repsPerRound,
                   lowerIsBetter: lowerIsBetter, hint: hint)
    }

    /// A new private workout snapshot; catalog edits never rewrite saved plans or history.
    func makeExercise() -> Exercise {
        let detail: String
        // 라운드형(신디)도 세트로만 센다: "신디 한 세트". 라운드·추가 횟수 입력을 만들지 않는다.
        if style == .rounds { detail = "한 세트" }
        else {
            switch unit.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "회": detail = "10회"
            case "초": detail = "60초"
            case "분": detail = "1분"
            default: detail = ""
            }
        }
        return Exercise(name: name, sets: 3, detail: detail)
    }

    static let defaults: [CatalogRecordType] = RecordType.defaults.enumerated().map { index, type in
        CatalogRecordType(id: "common-\(type.id)-v1", name: type.name, unit: type.unit,
                          style: type.style, repsPerRound: type.repsPerRound,
                          lowerIsBetter: type.lowerIsBetter, hint: type.hint,
                          active: true, position: index, revision: 1)
    }

    static func sorted(_ types: [CatalogRecordType]) -> [CatalogRecordType] {
        types.sorted { $0.position == $1.position ? $0.id < $1.id : $0.position < $1.position }
    }
}

struct RecordCatalogCache: Codable {
    var project: String
    var types: [CatalogRecordType]
    var fetchedAt: Date
}

extension AppData {
    /// Apply only a successfully fetched server catalog, never the startup fallback list.
    /// The user requested removal from plans, journals and frozen achievements alike.
    func removingUnregisteredWorkouts(catalog: [CatalogRecordType]) -> AppData {
        let active = catalog.filter(\.active)
        let names = Set(active.map { Self.exerciseKey($0.name) })
        let typeIDs = Set(active.map(\.id) + recordTypes.filter {
            names.contains(Self.exerciseKey($0.name))
        }.map(\.id))
        func plan(_ original: DayPlan) -> DayPlan {
            var copy = original
            copy.exercises.removeAll { !names.contains(Self.exerciseKey($0.name)) }
            return copy
        }
        func session(_ original: WorkoutSession) -> WorkoutSession? {
            var copy = original
            copy.plan = plan(copy.plan)
            guard !copy.plan.exercises.isEmpty else { return nil }
            let keys = Set(copy.plan.exercises.map { $0.id.uuidString })
            copy.completedSets = copy.completedSets.filter { keys.contains($0.key) }
            copy.actualReps = copy.actualReps.filter { keys.contains($0.key) }
            copy.actualWeights = copy.actualWeights.filter { keys.contains($0.key) }
            copy.recordReps = copy.recordReps.filter { keys.contains($0.key) }
            copy.recordTotals = copy.recordTotals.filter { keys.contains($0.key) }
            copy.recordEntries = copy.recordEntries.filter { keys.contains($0.key) }.mapValues {
                $0.map { entry in entry.flatMap { typeIDs.contains($0.typeID) ? $0 : nil } }
            }
            return copy
        }
        var copy = self
        copy.week = week.map(plan)
        // Retain empty dated plans so the weekly fallback cannot restore removed exercises.
        copy.scheduledPlans = scheduledPlans.mapValues(plan)
        copy.exerciseLibrary.removeAll { !names.contains(Self.exerciseKey($0.name)) }
        copy.activeWorkout = activeWorkout.flatMap(session)
        copy.workouts = workouts.compactMap(session)
        copy.recordWorkouts = recordWorkouts.map { $0.compactMap(session) }
        copy.recordTypes.removeAll { !typeIDs.contains($0.id) }
        copy.records.removeAll { !typeIDs.contains($0.typeID) }
        copy.bestRecordEntries = bestRecordEntries.map { $0.filter { typeIDs.contains($0.typeID) } }
        let sessions = copy.workouts + (copy.recordWorkouts ?? []) + [copy.activeWorkout].compactMap { $0 }
        let exercises = copy.week.flatMap(\.exercises) + copy.scheduledPlans.values.flatMap(\.exercises)
            + copy.exerciseLibrary + sessions.flatMap { $0.plan.exercises }
        let keys = Set(exercises.map { $0.id.uuidString })
        copy.logs = logs.compactMap { original in
            var log = original
            log.doneSets = log.doneSets.filter { keys.contains($0.key) }
            return log.doneSets.isEmpty ? nil : log
        }
        return copy
    }

    /// Creation and renaming require an active registration, even when called outside an editor.
    func introducesUnregisteredWorkout(from original: AppData, catalog: [CatalogRecordType]) -> Bool {
        func exercises(_ data: AppData) -> [Exercise] {
            data.week.flatMap(\.exercises) + data.scheduledPlans.values.flatMap(\.exercises)
                + data.exerciseLibrary + (data.activeWorkout?.plan.exercises ?? [])
                + data.workouts.flatMap { $0.plan.exercises }
        }
        let old = exercises(original)
        return exercises(self).contains { exercise in
            !old.contains { $0.id == exercise.id && Self.exerciseKey($0.name) == Self.exerciseKey(exercise.name) }
                && !isRegisteredExercise(exercise, catalog: catalog)
        }
    }

    func isRegisteredExercise(_ exercise: Exercise, catalog: [CatalogRecordType]) -> Bool {
        catalog.contains { $0.active && Self.exerciseKey($0.name) == Self.exerciseKey(exercise.name) }
    }

    /// Keep old personal records comparable under the matching administrator definition.
    /// This projection never rewrites historical IDs in the account backup.
    func recordProjection(catalog: [CatalogRecordType]) -> AppData {
        var result = self
        result.records = bestRecordEntries ?? records
        for old in recordTypes {
            guard let current = catalog.first(where: {
                Self.exerciseKey($0.name) == Self.exerciseKey(old.name) && $0.unit == old.unit
                    && $0.style == old.style && $0.repsPerRound == old.repsPerRound
                    && $0.lowerIsBetter == old.lowerIsBetter
            }), current.id != old.id else { continue }
            for index in result.records.indices where result.records[index].typeID == old.id {
                result.records[index].typeID = current.id
            }
        }
        if bestRecordEntries != nil { result.bestRecordEntries = result.records }
        result.recordTypes = recordDisplayTypes(catalog: catalog)
        return result
    }
    /// This is a display projection only. Never replace the private backup's legacy definitions.
    func recordDisplayTypes(catalog: [CatalogRecordType]) -> [RecordType] {
        let common = CatalogRecordType.sorted(catalog).map(\.recordType)
        let ids = Set(common.map(\.id))
        return common + recordTypes.filter { !ids.contains($0.id) }
    }
}
