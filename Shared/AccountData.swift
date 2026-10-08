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
        return result
    }

    /// Apply only the app's edits to the latest disk snapshot, preserving concurrent widget checks.
    func applyingEdits(from base: AppData, to edited: AppData) -> AppData {
        var result = self
        if base.week != edited.week { result.week = edited.week }
        if base.recordTypes != edited.recordTypes { result.recordTypes = edited.recordTypes }
        if base.records != edited.records { result.records = edited.records }
        if base.defaultRest != edited.defaultRest { result.defaultRest = edited.defaultRest }
        if base.restSound != edited.restSound { result.restSound = edited.restSound }
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
                    let limit = result.scheduledPlans[day]?.exercises.first { $0.id.uuidString == key }?.sets ?? Int.max
                    result.logs[index].doneSets[key] = min(max(current + delta, 0), max(limit, 0))
                } else {
                    result.logs[index].doneSets.removeValue(forKey: key)
                }
            }
        }
        return result
    }
}
