import Foundation

@main
struct DailyChecks {
    static func main() throws {
        func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
            Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        }
        let monday = date(2026, 10, 5)
        let tuesday = date(2026, 10, 6)
        let wednesday = date(2026, 10, 7)
        let sunday = date(2026, 10, 11)
        var data = AppData.empty
        let workoutBefore = data.scheduledPlans
        var task = DailyItem(title: "제출", scheduledDate: monday)
        let undated = DailyItem(title: "정리")
        var habit = DailyItem(title: "독서", kind: .habit, startDate: monday)
        data.saveDailyItem(task)
        data.saveDailyItem(undated)
        data.saveDailyItem(habit)
        assert(data.dailyItems(on: monday).count == 2)
        assert(data.dailyItems(on: monday, includeUndated: true).count == 3)
        assert(!habit.occurs(on: date(2026, 10, 4)))
        assert(habit.occurs(on: sunday))
        habit.repeatRule = .weekdays
        habit.weekdays = [1, 3]
        assert(habit.occurs(on: monday) && habit.occurs(on: wednesday))
        assert(!habit.occurs(on: tuesday) && !habit.occurs(on: sunday))
        habit.repeatRule = .interval
        habit.intervalDays = 2
        assert(habit.occurs(on: monday) && habit.occurs(on: wednesday))
        assert(!habit.occurs(on: tuesday))
        // Calendar day arithmetic also covers year boundaries, leap days and DST.
        habit.startDate = date(2024, 2, 28)
        assert(habit.occurs(on: date(2024, 3, 1)) && !habit.occurs(on: date(2024, 2, 29)))
        habit.startDate = date(2026, 12, 31)
        assert(habit.occurs(on: date(2027, 1, 2)))
        habit.startDate = date(2026, 3, 7)
        assert(habit.occurs(on: date(2026, 3, 9)))
        habit.startDate = monday
        habit.repeatRule = .daily
        data.saveDailyItem(habit)
        data.skipDailyHabit(habit.id, on: tuesday)
        assert(data.dailyItems(on: tuesday).isEmpty)
        assert(data.dailyItems(on: wednesday).count == 1)
        data.toggleDailyCompletion(habit.id, on: tuesday)
        assert(data.dailyCompletions.isEmpty) // skipped dates cannot be completed accidentally
        data.toggleDailyCompletion(habit.id, on: monday, at: monday)
        data.skipDailyHabit(habit.id, on: monday)
        assert(data.dailyItems(on: monday).count == 2) // completed habit cannot be skipped
        data.toggleDailyCompletion(habit.id, on: wednesday, at: wednesday)
        assert(data.dailyCompletions.count == 2)
        data.toggleDailyCompletion(habit.id, on: monday)
        assert(data.dailyCompletions.count == 1 && data.isDailyComplete(habit, on: wednesday))
        data.toggleDailyCompletion(task.id, on: tuesday)
        assert(!data.isDailyComplete(task, on: tuesday))
        data.toggleDailyCompletion(task.id, on: monday, at: tuesday)
        task.title = "과제 제출"
        task.scheduledDate = wednesday
        data.saveDailyItem(task)
        assert(data.isDailyComplete(task, on: wednesday)) // moving a completed task doesn't duplicate it
        assert(data.dailyCompletions.contains { $0.title == "제출" && $0.day == DayKey.key(monday) })
        data.dailyItems.removeAll { $0.id == task.id }
        assert(data.dailyCompletions.contains { $0.itemID == task.id })
        data.toggleDailyCompletion(undated.id, on: sunday, at: sunday)
        assert(data.isDailyComplete(undated, on: monday)) // tasks complete once; habits once per date
        assert(data.scheduledPlans == workoutBefore && data.records.isEmpty && data.workouts.isEmpty)
        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(AppData.self, from: encoded)
        assert(data == decoded)
        var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacy.removeValue(forKey: "dailyItems")
        legacy.removeValue(forKey: "dailyCompletions")
        let migrated = try JSONDecoder().decode(AppData.self, from: JSONSerialization.data(withJSONObject: legacy))
        assert(migrated.dailyItems.isEmpty && migrated.dailyCompletions.isEmpty)
        assert(migrated.scheduledPlans == data.scheduledPlans && migrated.records == data.records)
        let imported = AppData.empty.importingGuest(data)
        assert(imported.dailyItems == data.dailyItems && imported.dailyCompletions == data.dailyCompletions)
        assert(imported.importingGuest(data) == imported)
        // App edits from a stale base must preserve a widget's concurrent workout check.
        var base = AppData.empty
        let exercise = Exercise(name: "푸쉬업", sets: 3, detail: "10회", restSeconds: 60)
        base.scheduledPlans[DayKey.key(monday)] = DayPlan(title: "운동", exercises: [exercise])
        var latest = base
        latest.changeSets(exercise.id, by: 1, on: monday)
        var edited = base
        edited.saveDailyItem(undated)
        edited.toggleDailyCompletion(undated.id, on: monday, at: monday)
        let merged = latest.applyingEdits(from: base, to: edited)
        assert(merged.doneSets(exercise, on: monday) == 1 && merged.dailyItems.count == 1 && merged.dailyCompletions.count == 1)
        var concurrent = edited
        concurrent.saveDailyItem(habit)
        var removal = edited
        removal.dailyItems.removeAll()
        removal.dailyCompletions.removeAll()
        let removed = concurrent.applyingEdits(from: edited, to: removal)
        assert(removed.dailyItems.count == 1 && removed.dailyItems[0].id == habit.id && removed.dailyCompletions.isEmpty)
        var emptyDraft = AppData.empty
        emptyDraft.saveDailyItem(DailyItem(title: "   "))
        assert(emptyDraft.dailyItems.isEmpty)
        print("Daily checks passed: recurrence, exceptions, snapshots, migration, account import and concurrent workout edits")
    }
}