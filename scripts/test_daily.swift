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
        try reminderChecks()
        print("Daily checks passed: recurrence, exceptions, snapshots, migration, account import, concurrent workout edits, unified repeat and reminders")
    }

    static func reminderChecks() throws {
        func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
        }
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        // 예전 형식 호환: 알림 필드가 없는 항목·데이터를 읽고, 새 필드는 예전 앱이 무시할 수 있는 선택 키로만 저장
        let oldItem = try JSONSerialization.data(withJSONObject: [
            "id": UUID().uuidString, "title": "예전 습관", "note": "", "kind": "habit", "startDate": 0,
            "repeatRule": "daily", "weekdays": [1], "intervalDays": 2, "skippedDays": []])
        let decodedOld = try decoder.decode(DailyItem.self, from: oldItem)
        assert(decodedOld.reminderTime == nil && decodedOld.isRepeating && decodedOld.repeatChoice == .daily)
        var withSettings = AppData.empty
        withSettings.dailyReminders.morningSummary = ReminderTime(hour: 8, minute: 0)
        var json = try JSONSerialization.jsonObject(with: encoder.encode(withSettings)) as! [String: Any]
        assert(json["dailyReminders"] != nil)
        json.removeValue(forKey: "dailyReminders")
        let oldData = try decoder.decode(AppData.self, from: JSONSerialization.data(withJSONObject: json))
        assert(oldData.dailyReminders == DailyReminderSettings() && oldData.dailyReminders.enabled && oldData.dailyReminders.morningSummary == nil)
        let partial = try decoder.decode(DailyReminderSettings.self, from: Data("{\"sound\":false}".utf8))
        assert(partial.enabled && !partial.sound)
        assert(ReminderTime(hour: 25, minute: -3) == ReminderTime(hour: 23, minute: 0))
        assert(ReminderTime(hour: 7, minute: 5).label == "07:05")
        assert(DayKey.date(fromKey: "2026-10-05").map { DayKey.key($0) } == "2026-10-05")
        assert(DayKey.date(fromKey: "2026-02-30") == nil && DayKey.date(fromKey: "bad") == nil)

        // 반복 선택 하나로 한 번/반복 표현
        var item = DailyItem(title: "독서")
        assert(item.repeatChoice == .none && item.isUndated)
        item.repeatChoice = .weekdays
        assert(item.kind == .habit && item.repeatRule == .weekdays && item.isRepeating)
        item.repeatChoice = .interval
        assert(item.repeatRule == .interval)

        // 반복 → 안 함: 예전 날짜별 완료 때문에 끝난 것으로 보이지 않게 새 항목으로 저장, 기록은 보존
        let monday = at(2026, 10, 5, 12)
        var data = AppData.empty
        var habit = DailyItem(title: "스트레칭", kind: .habit, startDate: monday)
        data.saveDailyItemEditing(habit)
        data.toggleDailyCompletion(habit.id, on: monday, at: monday)
        habit.repeatChoice = .none
        habit.scheduledDate = at(2026, 10, 9, 12)
        habit.skippedDays = ["2026-10-06"]
        data.saveDailyItemEditing(habit)
        assert(data.dailyItems.count == 1 && data.dailyItems[0].id != habit.id && data.dailyItems[0].skippedDays.isEmpty)
        assert(!data.isDailyComplete(data.dailyItems[0], on: at(2026, 10, 9, 12)))
        assert(data.dailyCompletions.count == 1 && data.dailyCompletions[0].itemID == habit.id)
        // 한 번 → 반복은 같은 항목 유지, 날짜 미정이면 알림 제거
        var once = DailyItem(title: "정리", reminderTime: ReminderTime(hour: 9, minute: 0))
        data.saveDailyItemEditing(once)
        assert(data.dailyItems.first { $0.id == once.id }?.reminderTime == nil)
        once.repeatChoice = .daily
        once.startDate = monday
        data.saveDailyItemEditing(once)
        assert(data.dailyItems.contains { $0.id == once.id && $0.isRepeating })

        // 알림 완료 버튼: 되돌리지 않고 한 번만 기록
        assert(data.markDailyComplete(once.id, on: monday, at: monday))
        assert(!data.markDailyComplete(once.id, on: monday, at: monday))
        assert(data.isDailyComplete(once, on: monday))
        assert(!data.markDailyComplete(UUID(), on: monday))

        // 2주 예약 계획
        var plan = AppData.empty
        let daily = DailyItem(title: "독서", kind: .habit, startDate: monday, reminderTime: ReminderTime(hour: 21, minute: 0))
        let dated = DailyItem(title: "과제 제출", note: "보고서", scheduledDate: at(2026, 10, 7, 12), reminderTime: ReminderTime(hour: 9, minute: 30))
        let undated = DailyItem(title: "언젠가", reminderTime: ReminderTime(hour: 9, minute: 0))
        let silent = DailyItem(title: "알림 없음", kind: .habit, startDate: monday)
        plan.dailyItems = [daily, dated, undated, silent]
        let now = at(2026, 10, 5, 20)
        var planned = plan.plannedReminders(now: now)
        assert(planned.count == 15, "독서 14일 + 과제 1개 (\(planned.count))")
        assert(planned[0].fireDate == at(2026, 10, 5, 21) && planned[0].itemID == daily.id && planned[0].day == "2026-10-05")
        assert(planned.contains { $0.itemID == dated.id && $0.fireDate == at(2026, 10, 7, 9, 30) && $0.body == "보고서" })
        assert(!planned.contains { $0.itemID == undated.id || $0.itemID == silent.id })
        assert(zip(planned, planned.dropFirst()).allSatisfy { $0.fireDate <= $1.fireDate })
        assert(Set(planned.map(\.id)).count == planned.count && planned.allSatisfy { $0.id.hasPrefix(AppData.reminderPrefix) })
        assert(planned.allSatisfy { $0.fireDate > now && $0.fireDate < at(2026, 10, 19, 0) })
        // 이미 지난 시각, 완료한 날, 건너뛴 날은 울리지 않음
        assert(!plan.plannedReminders(now: at(2026, 10, 5, 21, 30)).contains { $0.day == "2026-10-05" })
        plan.toggleDailyCompletion(daily.id, on: monday, at: now)
        plan.skipDailyHabit(daily.id, on: at(2026, 10, 6, 12))
        planned = plan.plannedReminders(now: now)
        assert(!planned.contains { $0.itemID == daily.id && ($0.day == "2026-10-05" || $0.day == "2026-10-06") })
        plan.toggleDailyCompletion(dated.id, on: at(2026, 10, 7, 12), at: now)
        assert(!plan.plannedReminders(now: now).contains { $0.itemID == dated.id })
        // 아침 요약·저녁 확인: 남은 일상이 있는 날만
        plan.dailyReminders.morningSummary = ReminderTime(hour: 8, minute: 0)
        plan.dailyReminders.eveningCheck = ReminderTime(hour: 22, minute: 0)
        planned = plan.plannedReminders(now: now)
        assert(planned.contains { $0.kind == .evening && $0.day == "2026-10-05" && $0.title == "아직 1개 남았어요" && $0.body == "알림 없음" })
        assert(!planned.contains { $0.kind == .morning && $0.day == "2026-10-05" }, "이미 지난 아침 요약은 예약하지 않음")
        plan.toggleDailyCompletion(silent.id, on: monday, at: now)
        planned = plan.plannedReminders(now: now)
        assert(!planned.contains { $0.kind == .evening && $0.day == "2026-10-05" }, "오늘 모두 완료하면 저녁 확인 없음")
        assert(planned.contains { $0.kind == .morning && $0.day == "2026-10-06" && $0.title == "오늘 일상 1개" })
        assert(planned.contains { $0.kind == .morning && $0.day == "2026-10-07" && $0.title == "오늘 일상 2개" })
        // 전체 끄기, 64개 제한 안쪽으로 가까운 순서만
        plan.dailyReminders.enabled = false
        assert(plan.plannedReminders(now: now).isEmpty)
        var many = AppData.empty
        for index in 0..<10 {
            many.dailyItems.append(DailyItem(title: "항목\(index)", kind: .habit, startDate: monday,
                                             reminderTime: ReminderTime(hour: 6 + index, minute: 0)))
        }
        let capped = many.plannedReminders(now: at(2026, 10, 5, 5))
        assert(capped.count == AppData.reminderLimit && capped.last!.fireDate < at(2026, 10, 11, 0))
        // 설정은 계정 동기화 병합에 포함
        var base = AppData.empty, edited = AppData.empty
        edited.dailyReminders.sound = false
        assert(!AppData.empty.applyingEdits(from: base, to: edited).dailyReminders.sound)
        base = edited
        assert(!edited.applyingEdits(from: base, to: base).dailyReminders.sound)
    }
}