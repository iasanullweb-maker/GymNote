import Foundation

@main
struct ModelChecks {
    static func main() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var original = AppData.sample
        let today = Date()
        let key = DayKey.key(today)
        let exercise = Exercise(name: "검증 운동", sets: 3, detail: "12회", restSeconds: 60)
        original.week[DayKey.weekdayIndex(today)] = DayPlan(title: "이전 루틴", exercises: [exercise])
        original.logs = [DayLog(day: key, doneSets: [exercise.id.uuidString: 2])]
        original.records = [RecordEntry(typeID: "pushup", date: today, value: 21)]

        // 이전 저장 형식으로 만든 뒤 실제 디코더로 이관한다.
        var legacy = try JSONSerialization.jsonObject(with: encoder.encode(original)) as! [String: Any]
        legacy.removeValue(forKey: "scheduledPlans")
        legacy.removeValue(forKey: "exerciseLibrary")
        legacy.removeValue(forKey: "activeWorkout")
        legacy.removeValue(forKey: "workouts")
        let migrated = try decoder.decode(AppData.self, from: JSONSerialization.data(withJSONObject: legacy))
        assert(migrated.plan(for: today).title == "이전 루틴")
        assert(migrated.doneSets(exercise, on: today) == 2, "완료 세트와 운동 ID 유지")
        assert(migrated.records == original.records, "최고 기록 유지")
        assert(migrated.week == original.week, "기존 루틴은 복사용으로 보존")
        assert(migrated.scheduledPlans.count == 7)
        assert(Set(migrated.exerciseLibrary.map(\.name)).count == migrated.exerciseLibrary.count)
        let dates = DayKey.weekDates(containing: today)
        assert(Calendar.current.component(.weekday, from: dates[0]) == 2)
        assert(dates.count == 7 && dates.contains { DayKey.key($0) == key })
        let followingWeek = Calendar.current.date(byAdding: .day, value: 7, to: today)!
        assert(migrated.plan(for: followingWeek).isRestDay, "일정은 자동 반복되지 않음")

        var edited = migrated
        var assigned = exercise
        assigned.id = UUID()
        edited.scheduledPlans[DayKey.key(followingWeek)] = DayPlan(title: "다음 운동", exercises: [assigned])
        edited.changeSets(assigned.id, by: 1, on: followingWeek)
        assert(edited.doneSets(assigned, on: followingWeek) == 1)
        assert(edited.doneSets(exercise, on: today) == 2, "날짜별 진행 분리")
        let templates = edited.exerciseLibrary
        edited.scheduledPlans[DayKey.key(followingWeek)]!.exercises[0].detail = "8회"
        assert(edited.exerciseLibrary == templates, "날짜별 수정은 운동 목록과 독립")
        let reloaded = try decoder.decode(AppData.self, from: encoder.encode(edited))
        assert(reloaded == edited, "저장 후 재로드")

        edited.scheduledPlans = [:]
        edited.exerciseLibrary = []
        let empty = try decoder.decode(AppData.self, from: encoder.encode(edited))
        assert(empty.scheduledPlans.isEmpty && empty.exerciseLibrary.isEmpty, "빈 목록은 다시 생성하지 않음")
        assert(migrated.activeWorkout == nil && migrated.workouts.isEmpty)
        let calendar = Calendar.current
        for year in [2024, 2026] {
            for month in 1...12 {
                let date = calendar.date(from: DateComponents(year: year, month: month, day: 15))!
                let grid = DayKey.monthDates(containing: date)
                assert(grid.count % 7 == 0 && grid.count >= 28 && grid.count <= 42)
                assert(calendar.component(.weekday, from: grid.first!) == 2)
                let inMonth = grid.filter { calendar.isDate($0, equalTo: date, toGranularity: .month) }
                assert(inMonth.count == calendar.range(of: .day, in: .month, for: date)!.count)
                assert(Set(grid.map { DayKey.key($0) }).count == grid.count)
            }
        }
        var training = migrated
        training.logs = []
        let first = Exercise(name: "푸쉬업", sets: 2, detail: "10회", restSeconds: 60)
        let second = Exercise(name: "플랭크", sets: 1, detail: "1분", restSeconds: 30)
        training.scheduledPlans[key] = DayPlan(title: "검증 계획", exercises: [first, second])
        assert(training.startWorkout(at: today))
        assert(!training.startWorkout(at: today), "진행 중 중복 시작 방지")
        assert(!training.finishWorkout(at: today), "완료 세트 없는 일지는 저장하지 않음")
        training.changeSets(first.id, by: 1, on: today)
        training.changeSets(first.id, by: -1, on: today)
        assert(training.activeWorkout?.done == 0)
        training.changeSets(first.id, by: 1, on: today)
        let resumed = try decoder.decode(AppData.self, from: encoder.encode(training))
        assert(resumed.activeWorkout == training.activeWorkout, "앱 재실행 시 세션 복원")
        training.scheduledPlans[key] = DayPlan(title: "수정된 계획", exercises: [])
        training.changeSets(first.id, by: 1, on: today)
        training.changeSets(second.id, by: 1, on: today)
        assert(training.activeWorkout == nil && training.workouts.count == 1, "마지막 세트 자동 저장")
        let workout = training.workouts[0]
        assert(workout.done == 3 && workout.day == key)
        assert(workout.plan.title == "검증 계획" && workout.plan.exercises[0].detail == "10회", "시작 당시 운동·횟수 보존")
        assert(training.records == migrated.records, "최고 기록과 운동 일지 분리")
        assert(!training.finishWorkout(at: today) && training.workouts.count == 1, "중복 저장 방지")
        training.scheduledPlans[DayKey.key(followingWeek)] = DayPlan(title: "중도 종료", exercises: [first])
        assert(training.startWorkout(at: followingWeek))
        training.changeSets(first.id, by: 1, on: followingWeek)
        assert(training.finishWorkout(at: followingWeek))
        assert(training.workouts.last?.done == 1)
        let finishedReload = try decoder.decode(AppData.self, from: encoder.encode(training))
        assert(finishedReload == training, "일지 저장 후 재로드")

        // 날짜가 지난 운동 정리
        var stale = AppData(week: AppData.sample.week)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let staleExercise = Exercise(name: "어제 운동", sets: 3, detail: "10회", restSeconds: 0)
        stale.scheduledPlans[DayKey.key(yesterday)] = DayPlan(title: "어제", exercises: [staleExercise])
        assert(stale.startWorkout(at: yesterday))
        stale.changeSets(staleExercise.id, by: 1, on: yesterday)
        assert(stale.closeStaleWorkout(now: today) && stale.activeWorkout == nil, "어제 운동 정리")
        assert(stale.workouts.count == 1 && stale.workouts[0].endedAt == nil, "완료 세트 있으면 일지로 저장")
        assert(!stale.closeStaleWorkout(now: today), "정리할 운동 없음")
        assert(stale.startWorkout(at: yesterday) == true && stale.closeStaleWorkout(now: today), "0세트 지난 운동")
        assert(stale.workouts.count == 1, "0세트 지난 운동은 버림")

        // 같은 날 두 번째 운동은 0세트부터, 이전 일지 보존
        var twice = AppData(week: AppData.sample.week)
        let move = Exercise(name: "스쿼트", sets: 2, detail: "20회", restSeconds: 0)
        twice.scheduledPlans[key] = DayPlan(title: "하체", exercises: [move])
        assert(twice.startWorkout(at: today))
        twice.changeSets(move.id, by: 1, on: today)
        twice.changeSets(move.id, by: 1, on: today)
        assert(twice.activeWorkout == nil && twice.hasSavedWorkout(on: today), "첫 운동 자동 저장")
        assert(twice.startWorkout(at: today), "저장 후 새 운동 시작 가능")
        assert(twice.activeWorkout?.done == 0 && twice.doneSets(move, on: today) == 0, "새 운동은 0세트")
        assert(twice.workouts[0].done == 2, "이전 일지 보존")

        // 위젯 체크로 운동 자동 시작
        var widget = AppData(week: AppData.sample.week)
        widget.scheduledPlans[key] = DayPlan(title: "위젯", exercises: [move])
        widget.completeSetFromWidget(move.id, now: today)
        assert(widget.activeWorkout?.done == 1, "위젯 첫 체크로 운동 시작")
        widget.completeSetFromWidget(move.id, now: today)
        assert(widget.activeWorkout == nil && widget.workouts.count == 1, "위젯으로 끝까지 하면 일지 저장")
        widget.completeSetFromWidget(move.id, now: today)
        assert(widget.workouts.count == 1 && widget.activeWorkout == nil, "저장 후 위젯 탭은 새 일지를 만들지 않음")

        // 주간 반복: 미래 날짜만, 새 운동 ID
        var weekly = AppData(week: AppData.sample.week)
        let monday = DayKey.weekDates(containing: today)[0]
        weekly.scheduledPlans = [:]
        for (i, day) in DayKey.weekDates(containing: monday).enumerated() where i % 2 == 0 {
            weekly.scheduledPlans[DayKey.key(day)] = DayPlan(title: "반복 \(i)", exercises: [move])
        }
        let before = weekly.scheduledPlans
        weekly.repeatWeek(containing: monday, weeks: 2, today: today)
        for (i, day) in DayKey.weekDates(containing: monday).enumerated() {
            assert(weekly.scheduledPlans[DayKey.key(day)] == before[DayKey.key(day)], "이번 주는 그대로")
            for w in 1...2 {
                let target = Calendar.current.date(byAdding: .day, value: 7 * w, to: day)!
                let copied = weekly.plan(for: target)
                assert(copied.title == (i % 2 == 0 ? "반복 \(i)" : "휴식"), "요일별 복사")
                if i % 2 == 0 { assert(copied.exercises[0].id != move.id, "복사본은 새 운동 ID") }
            }
        }
        // −/+ 간격 설정 저장·이전 형식 기본값
        var stepData = AppData(week: AppData.sample.week)
        assert(stepData.restStep == 15, "기본 간격 15초")
        stepData.restStep = 5
        let stepReload = try decoder.decode(AppData.self, from: encoder.encode(stepData))
        assert(stepReload.restStep == 5, "간격 저장")
        var noStep = try JSONSerialization.jsonObject(with: encoder.encode(stepData)) as! [String: Any]
        noStep.removeValue(forKey: "restStep")
        let oldFile = try decoder.decode(AppData.self, from: JSONSerialization.data(withJSONObject: noStep))
        assert(oldFile.restStep == 15, "예전 파일은 15초")
        // 운동별 휴식 제거: 예전 필드가 있어도, 없어도 읽힘 / 다른 값은 그대로 유지
        let withRest = Exercise(name: "예전 운동", sets: 4, detail: "8회", restSeconds: 120)
        let withRestReload = try decoder.decode(Exercise.self, from: encoder.encode(withRest))
        assert(withRestReload == withRest, "예전 휴식 필드 유지")
        var noRest = try JSONSerialization.jsonObject(with: encoder.encode(withRest)) as! [String: Any]
        noRest.removeValue(forKey: "restSeconds")
        let noRestReload = try decoder.decode(Exercise.self, from: JSONSerialization.data(withJSONObject: noRest))
        assert(noRestReload.restSeconds == 0 && noRestReload.name == "예전 운동" && noRestReload.sets == 4 && noRestReload.id == withRest.id, "휴식 필드 없는 운동")
        assert(Exercise(name: "새 운동", sets: 3, detail: "10회").restSeconds == 0, "새 운동은 운동별 휴식 없음")
        // 표시만 분·초로 변환. 저장된 초 및 타이머 종료 시각은 변경하지 않는다.
        for (seconds, text) in [(-1, "0초"), (0, "0초"), (5, "5초"), (59, "59초"),
                                (60, "1분 0초"), (90, "1분 30초"), (125, "2분 5초"), (600, "10분 0초")] {
            assert(RestDuration.text(seconds: seconds) == text)
        }
        let restEnd = today.addingTimeInterval(90)
        assert(RestDuration.remaining(until: restEnd, at: today) == 90)
        assert(RestDuration.remaining(until: restEnd, at: restEnd.addingTimeInterval(-0.2)) == 1)
        assert(RestDuration.remaining(until: restEnd, at: restEnd) == 0)
        assert(RestDuration.remaining(until: restEnd, at: restEnd.addingTimeInterval(5)) == 0)

        // 하루 여러 일지, 자정 이후 종료, 계획 변경·삭제와 독립적인 날짜 조회.
        let journalDay = calendar.startOfDay(for: today)
        let morning = WorkoutSession(startedAt: journalDay.addingTimeInterval(3600), plan: DayPlan(title: "아침", exercises: [move]), completedSets: [move.id.uuidString: 1])
        let night = WorkoutSession(startedAt: journalDay.addingTimeInterval(23 * 3600), endedAt: journalDay.addingTimeInterval(25 * 3600), plan: DayPlan(title: "저녁", exercises: [move]), completedSets: [move.id.uuidString: 2])
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: journalDay)!
        let next = WorkoutSession(startedAt: tomorrow.addingTimeInterval(3600), plan: morning.plan)
        var journal = AppData(week: [])
        journal.workouts = [morning, next, night]
        assert(journal.workouts(on: today).map(\.id) == [night.id, morning.id])
        assert(journal.workouts(on: tomorrow).map(\.id) == [next.id])
        assert(journal.workouts(on: calendar.date(byAdding: .day, value: -1, to: today)!).isEmpty)
        let journalReload = try decoder.decode(AppData.self, from: encoder.encode(journal))
        assert(journalReload.workouts(on: today) == [night, morning])
        // Actual repetitions remain independent from the plan, survive reload, and undo with the set.
        assert(first.plannedReps == 10)
        assert(Exercise(name: "런지", sets: 2, detail: "다리당 12회").plannedReps == 12)
        for detail in ["1분", "최대의 70%", "8~12회", "10회 + 5회", "1.5회", "-10회"] {
            assert(Exercise(name: "기준", sets: 1, detail: detail).plannedReps == nil)
        }
        var repetitions = AppData(week: [])
        repetitions.scheduledPlans[key] = DayPlan(title: "실제 횟수", exercises: [first, second])
        repetitions.startWorkout(at: today)
        let sessionID = repetitions.activeWorkout!.id
        repetitions.changeSets(first.id, by: 1, on: today, actualReps: 8)
        assert(repetitions.activeWorkout!.repetitions(first, set: 0) == 8)
        assert(repetitions.activeWorkout!.plan.exercises[0].detail == "10회")
        repetitions.changeSets(first.id, by: 1, on: today, actualReps: 12)
        repetitions.changeSets(first.id, by: -1, on: today)
        assert(repetitions.activeWorkout!.actualReps[first.id.uuidString] == [8])
        repetitions.changeSets(first.id, by: 1, on: today)
        assert(repetitions.activeWorkout!.repetitions(first, set: 1) == 10, "다음 세트는 계획 기준")
        repetitions.updateRepetitions(sessionID: sessionID, exerciseID: first.id, set: 0, value: 0)
        assert(repetitions.activeWorkout!.repetitions(first, set: 0) == 0)
        repetitions.changeSets(second.id, by: 1, on: today)
        assert(repetitions.workouts[0].repetitions(second, set: 0) == nil, "시간을 횟수로 기록하지 않음")
        repetitions.updateRepetitions(sessionID: sessionID, exerciseID: first.id, set: 1, value: 9)
        let repetitionsReload = try decoder.decode(AppData.self, from: encoder.encode(repetitions))
        assert(repetitionsReload == repetitions && repetitionsReload.workouts[0].repetitions(first, set: 1) == 9)
        var oldSession = try JSONSerialization.jsonObject(with: encoder.encode(repetitions.workouts[0])) as! [String: Any]
        oldSession.removeValue(forKey: "actualReps")
        let legacySession = try decoder.decode(WorkoutSession.self, from: JSONSerialization.data(withJSONObject: oldSession))
        assert(legacySession.done == 3 && legacySession.repetitions(first, set: 0) == nil, "예전 일지 실제 횟수는 미기록")
        print("Model checks passed: migration, calendars, workout sessions, journals, persistence, repetitions, stale/twice/widget/repeat")
    }
}
