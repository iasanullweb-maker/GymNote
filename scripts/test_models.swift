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
        print("Model checks passed: migration, calendars, workout sessions, journals, persistence")
    }
}
