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
        print("Model checks passed: migration, schedules, progress, library, persistence")
    }
}
