import Foundation

/// A revision identifies the exact local snapshot uploaded; serverVersion enables compare-and-swap.
struct StoredWorkout: Codable {
    var data: AppData
    var revision = UUID()
    var serverVersion: Int64 = 0
    var dirty = true
    var importedGuest = false
}

struct StoreSelection: Codable, Equatable {
    var userID: UUID?
    var generation = UUID()
    var scope: String { userID?.uuidString.lowercased() ?? "guest" }
}

extension AppData {
    static var empty: AppData {
        var result = AppData(week: Array(repeating: DayPlan(title: "휴식", exercises: []), count: 7))
        result.scheduledPlans = [:]
        result.exerciseLibrary = []
        return result
    }

    /// Import without replacing existing account records or settings. IDs make re-import idempotent.
    func importingGuest(_ guest: AppData) -> AppData {
        var result = self
        if result.week.allSatisfy(\.isRestDay) { result.week = guest.week }
        var typeIDs: [String: String] = [:]
        for type in guest.recordTypes {
            if let existing = result.recordTypes.first(where: { $0.id == type.id }), existing != type {
                var copy = type
                copy.id = "guest-" + type.id
                while let collision = result.recordTypes.first(where: { $0.id == copy.id }), collision != copy {
                    copy.id = "guest-" + copy.id
                }
                typeIDs[type.id] = copy.id
                if !result.recordTypes.contains(where: { $0.id == copy.id }) { result.recordTypes.append(copy) }
            } else if !result.recordTypes.contains(where: { $0.id == type.id }) {
                result.recordTypes.append(type)
            }
        }
        for entry in guest.records where !result.records.contains(where: { $0.id == entry.id }) {
            var copy = entry
            copy.typeID = typeIDs[entry.typeID] ?? entry.typeID
            result.records.append(copy)
        }
        for exercise in guest.exerciseLibrary where !result.exerciseLibrary.contains(where: { $0.id == exercise.id }) {
            result.exerciseLibrary.append(exercise)
        }
        for (day, incoming) in guest.scheduledPlans {
            if let current = result.scheduledPlans[day] {
                var merged = current
                merged.exercises += incoming.exercises.filter { ex in !current.exercises.contains(where: { $0.id == ex.id }) }
                result.scheduledPlans[day] = merged
            } else {
                result.scheduledPlans[day] = incoming
            }
        }
        for log in guest.logs {
            if let index = result.logs.firstIndex(where: { $0.day == log.day }) {
                for (id, value) in log.doneSets where result.logs[index].doneSets[id] == nil {
                    result.logs[index].doneSets[id] = value
                }
            } else { result.logs.append(log) }
        }
        for workout in guest.workouts where !result.workouts.contains(where: { $0.id == workout.id }) {
            result.workouts.append(workout)
        }
        if var incoming = guest.activeWorkout, !result.workouts.contains(where: { $0.id == incoming.id }) {
            if result.activeWorkout == nil { result.activeWorkout = incoming }
            else if result.activeWorkout?.id != incoming.id, incoming.done > 0 {
                // Keep the account's current session; preserve guest progress as a journal entry.
                incoming.endedAt = max(Date(), incoming.startedAt)
                result.workouts.append(incoming)
            }
        }
        for item in guest.dailyItems where !result.dailyItems.contains(where: { $0.id == item.id }) {
            result.dailyItems.append(item)
        }
        for completion in guest.dailyCompletions where !result.dailyCompletions.contains(where: {
            $0.id == completion.id || ($0.itemID == completion.itemID && $0.day == completion.day)
        }) {
            result.dailyCompletions.append(completion)
        }
        return result
    }

    /// Apply only the app's edits to the latest disk snapshot, preserving concurrent widget checks.
    func applyingEdits(from base: AppData, to edited: AppData) -> AppData {
        var result = self
        result.dailyItems = mergeDailyEdits(latest: result.dailyItems, base: base.dailyItems, edited: edited.dailyItems)
        result.dailyCompletions = mergeDailyEdits(latest: result.dailyCompletions, base: base.dailyCompletions, edited: edited.dailyCompletions)
        if base.week != edited.week { result.week = edited.week }
        if base.recordTypes != edited.recordTypes { result.recordTypes = edited.recordTypes }
        if base.records != edited.records { result.records = edited.records }
        if base.defaultRest != edited.defaultRest { result.defaultRest = edited.defaultRest }
        if base.restSound != edited.restSound { result.restSound = edited.restSound }
        if base.restStep != edited.restStep { result.restStep = edited.restStep }
        if base.scheduledPlans != edited.scheduledPlans { result.scheduledPlans = edited.scheduledPlans }
        if base.exerciseLibrary != edited.exerciseLibrary { result.exerciseLibrary = edited.exerciseLibrary }
        let days = Set(base.logs.map(\.day) + edited.logs.map(\.day))
        for day in days {
            if base.logs.contains(where: { $0.day == day }), !edited.logs.contains(where: { $0.day == day }) {
                result.logs.removeAll { $0.day == day }
                continue
            }
            let before = base.logs.first { $0.day == day }?.doneSets ?? [:]
            let after = edited.logs.first { $0.day == day }?.doneSets ?? [:]
            guard before != after else { continue }
            if !result.logs.contains(where: { $0.day == day }) { result.logs.append(DayLog(day: day)) }
            let index = result.logs.firstIndex { $0.day == day }!
            for key in Set(before.keys).union(after.keys) where before[key] != after[key] {
                if let next = after[key] {
                    let delta = next - (before[key] ?? 0)
                    let current = result.logs[index].doneSets[key] ?? 0
                    let sessionPlan = [edited.activeWorkout, base.activeWorkout, result.activeWorkout]
                        .compactMap { $0 }.first { $0.day == day }?.plan
                    let limit = (sessionPlan ?? result.scheduledPlans[day])?.exercises.first { $0.id.uuidString == key }?.sets ?? Int.max
                    result.logs[index].doneSets[key] = min(max(current + delta, 0), max(limit, 0))
                } else {
                    result.logs[index].doneSets.removeValue(forKey: key)
                }
            }
        }
        // Journal edits apply by ID so a widget finishing another session cannot be overwritten.
        for previous in base.workouts where !edited.workouts.contains(where: { $0.id == previous.id }) {
            result.workouts.removeAll { $0.id == previous.id }
        }
        for workout in edited.workouts where base.workouts.first(where: { $0.id == workout.id }) != workout {
            if let index = result.workouts.firstIndex(where: { $0.id == workout.id }) { result.workouts[index] = workout }
            else { result.workouts.append(workout) }
        }
        if base.activeWorkout != edited.activeWorkout {
            // An already finished session must not reappear when the app saves a stale snapshot.
            if result.activeWorkout?.id == base.activeWorkout?.id {
                result.activeWorkout = edited.activeWorkout
            }
            if let session = result.activeWorkout, result.workouts.contains(where: { $0.id == session.id }) {
                result.activeWorkout = nil
            }
        }
        let touchedSessionIDs = Set([base.activeWorkout?.id, edited.activeWorkout?.id].compactMap { $0 })
        func withMergedProgress(_ session: WorkoutSession) -> WorkoutSession {
            var copy = session
            let counts = result.logs.first { $0.day == session.day }?.doneSets ?? [:]
            for exercise in session.plan.exercises {
                if let count = counts[exercise.id.uuidString] {
                    copy.completedSets[exercise.id.uuidString] = min(max(count, 0), max(exercise.sets, 0))
                }
            }
            return copy
        }
        if edited.activeWorkout == nil, let previous = base.activeWorkout,
           let latest = activeWorkout, latest.id == previous.id,
           !result.workouts.contains(where: { $0.id == previous.id }), result.activeWorkout == nil {
            var preserved = withMergedProgress(latest)
            if preserved.done > 0 {
                preserved.endedAt = max(Date(), preserved.startedAt)
                result.workouts.append(preserved)
            }
        }
        if let session = result.activeWorkout, touchedSessionIDs.contains(session.id) {
            result.activeWorkout = withMergedProgress(session)
            if let updated = result.activeWorkout, updated.total > 0, updated.done == updated.total {
                result.finishWorkout()
            }
        }
        for index in result.workouts.indices where touchedSessionIDs.contains(result.workouts[index].id) {
            result.workouts[index] = withMergedProgress(result.workouts[index])
        }
        return result
    }
}

private func mergeDailyEdits<T: Identifiable & Equatable>(latest: [T], base: [T], edited: [T]) -> [T] {
    var result = latest
    for previous in base where !edited.contains(where: { $0.id == previous.id }) {
        result.removeAll { $0.id == previous.id }
    }
    for value in edited where base.first(where: { $0.id == value.id }) != value {
        if let index = result.firstIndex(where: { $0.id == value.id }) { result[index] = value }
        else { result.append(value) }
    }
    return result
}