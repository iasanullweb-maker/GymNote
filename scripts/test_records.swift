import Foundation

@main
struct RecordChecks {
    static func main() throws {
        func at(_ month: Int, _ day: Int, _ hour: Int = 18) -> Date {
            Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
        }
        func session(_ date: Date, _ items: [(Exercise, [Int?], Int)], ended: Bool = true) -> WorkoutSession {
            var value = WorkoutSession(startedAt: date, plan: DayPlan(title: "운동", exercises: items.map(\.0)))
            for (exercise, reps, done) in items {
                value.completedSets[exercise.id.uuidString] = done
                value.actualReps[exercise.id.uuidString] = reps
            }
            if ended { value.endedAt = date.addingTimeInterval(1800) }
            return value
        }
        let rest = DayPlan(title: "휴식", exercises: [])
        var data = AppData(week: Array(repeating: rest, count: 7))
        assert(data.recordTypes.map(\.name) == ["푸쉬업", "풀업", "신디"])

        // 같은 운동 판단: 공백·대소문자 무시
        assert(AppData.exerciseKey(" 에어 스쿼트 ") == AppData.exerciseKey("에어스쿼트"))
        assert(AppData.exerciseKey("Push Up") == AppData.exerciseKey("pushup"))

        let monday = at(10, 5), mondayLater = at(10, 5, 21), tuesday = at(10, 6), wednesday = at(10, 7)
        let push = Exercise(name: "푸쉬업", sets: 3, detail: "10회")
        let pushAgain = Exercise(name: "푸쉬업 ", sets: 2, detail: "10회")
        let squat = Exercise(name: "에어 스쿼트", sets: 2, detail: "20회")
        // 실제 횟수 없는 세트(nil)와 되돌린 세트(완료 수 밖)는 제외, 계획 횟수는 쓰지 않음
        data.workouts = [
            session(monday, [(push, [10, 12, nil], 3), (squat, [20, 25, 99], 2)]),
            session(mondayLater, [(pushAgain, [15], 1)]),
        ]
        var records = data.exerciseRecords()
        let pushKey = AppData.exerciseKey("푸쉬업"), squatKey = AppData.exerciseKey("에어스쿼트")
        assert(records[pushKey]?.bestSet == AutoRecord(value: 15, date: mondayLater), "세트 최고 15")
        assert(records[pushKey]?.bestDay == AutoRecord(value: 37, date: monday), "같은 날 두 운동 합산 10+12+15")
        assert(records[squatKey]?.bestSet?.value == 25 && records[squatKey]?.bestDay?.value == 45, "되돌린 세트(99) 제외")

        // 다음 날 더 많은 총량 → 하루 최고 갱신, 세트 최고는 유지
        data.workouts.append(session(tuesday, [(push, [14, 14, 14], 3)]))
        records = data.exerciseRecords()
        assert(records[pushKey]?.bestDay == AutoRecord(value: 42, date: tuesday))
        assert(records[pushKey]?.bestSet == AutoRecord(value: 15, date: mondayLater))
        // 같은 값은 먼저 달성한 날 유지
        data.workouts.append(session(wednesday, [(push, [15, 0, 0], 3)]))
        assert(data.exerciseRecords()[pushKey]?.bestSet?.date == mondayLater)

        // 실제 횟수가 없는 예전 일지, 진행 중 운동은 포함하지 않음
        var legacy = session(wednesday, [(Exercise(name: "딥스", sets: 3, detail: "10회"), [], 3)])
        legacy.actualReps = [:]
        data.workouts.append(legacy)
        data.activeWorkout = session(wednesday, [(Exercise(name: "풀업", sets: 3, detail: "10회"), [30, 30, 30], 3)], ended: false)
        records = data.exerciseRecords()
        assert(records[AppData.exerciseKey("딥스")] == nil && records[AppData.exerciseKey("풀업")] == nil)
        data.activeWorkout = nil

        // 일지 수정·삭제 시 다시 계산
        data.updateRepetitions(sessionID: data.workouts[1].id, exerciseID: pushAgain.id, set: 0, value: 30)
        assert(data.exerciseRecords()[pushKey]?.bestSet?.value == 30)
        data.workouts.remove(at: 1)
        assert(data.exerciseRecords()[pushKey]?.bestSet?.value == 15)

        // 같은 이름의 수동 종목과 합치기: 숫자·'회'·높을수록 좋음만
        let pushType = data.recordTypes[0], cindy = data.recordTypes[2]
        assert(AppData.acceptsWorkoutRepetitions(pushType) && !AppData.acceptsWorkoutRepetitions(cindy))
        var timed = RecordType(name: "에어 스쿼트", unit: "초", lowerIsBetter: true)
        assert(!AppData.acceptsWorkoutRepetitions(timed))
        timed.unit = "회"
        assert(!AppData.acceptsWorkoutRepetitions(timed), "낮을수록 좋은 종목은 합치지 않음")
        let auto = data.exerciseRecords(for: pushType)
        assert(data.combinedBestSet(for: pushType, auto: auto)?.fromJournal == true && data.combinedBestSet(for: pushType, auto: auto)?.value == 15)
        data.addRecord(RecordEntry(typeID: pushType.id, date: at(10, 1), value: 20))
        let manualWins = data.combinedBestSet(for: pushType, auto: auto)
        assert(manualWins?.value == 20 && manualWins?.fromJournal == false, "수동 20 > 일지 15")
        assert(data.linkedRecordType(for: pushKey)?.id == pushType.id && data.linkedRecordType(for: squatKey) == nil)
        assert(data.unlinkedExerciseRecords().map(\.key) == [squatKey], "종목이 없는 운동만 자동 카드")

        // 신기록 알림: 수동 기록·이전 일지보다 좋아졌을 때만, 처음 생긴 기록은 알리지 않음
        var before = data.exerciseRecords()
        data.workouts.append(session(at(10, 8), [(push, [21, 21, 21], 3), (Exercise(name: "버피", sets: 1, detail: "10회"), [12], 1)]))
        var messages = data.recordImprovements(since: before)
        assert(messages == ["푸쉬업 한 세트 21회", "푸쉬업 하루 총량 63회"], "\(messages)")
        before = data.exerciseRecords()
        data.workouts.append(session(at(10, 9), [(push, [5], 1)]))
        messages = data.recordImprovements(since: before)
        assert(messages.isEmpty)

        // 위젯: 그날 계획한 운동(중복 제거, 3개), 운동 없는 날은 목록 위 종목
        let plannedDay = at(10, 12)
        data.scheduledPlans[DayKey.key(plannedDay)] = DayPlan(title: "상체", exercises: [
            Exercise(name: "푸쉬업", sets: 3, detail: "10회"), Exercise(name: "에어스쿼트", sets: 2, detail: "20회"),
            Exercise(name: " 푸쉬업", sets: 1, detail: "최대"), Exercise(name: "플랭크", sets: 3, detail: "1분"),
            Exercise(name: "풀업", sets: 3, detail: "5회"),
        ])
        let rows = data.recordSummaries(on: plannedDay)
        assert(rows.map(\.name) == ["푸쉬업", "에어스쿼트", "플랭크"], "\(rows.map(\.name))")
        assert(rows[0].setText == "21" && rows[0].dayText == "63")
        assert(rows[1].setText == "25" && rows[1].dayText == "45")
        assert(rows[2].setText == "–" && rows[2].dayText == nil)
        let restRows = data.recordSummaries(on: at(10, 13))
        assert(restRows.map(\.name) == ["푸쉬업", "풀업", "신디"])
        assert(restRows[0].setText == "21" && restRows[0].dayText == "63" && restRows[1].setText == "–")

        // 마지막 세트로 자동 종료되는 실제 흐름에서도 반영
        var flow = AppData(week: Array(repeating: rest, count: 7))
        let today = at(10, 20, 9)
        let lunge = Exercise(name: "런지", sets: 2, detail: "12회")
        flow.scheduledPlans[DayKey.key(today)] = DayPlan(title: "하체", exercises: [lunge])
        assert(flow.startWorkout(at: today))
        flow.changeSets(lunge.id, by: 1, on: today, actualReps: 12)
        flow.changeSets(lunge.id, by: 1, on: today, actualReps: 16)
        assert(flow.activeWorkout == nil && flow.workouts.count == 1, "마지막 세트로 자동 종료")
        let lungeRecords = flow.exerciseRecords()[AppData.exerciseKey("런지")]
        assert(lungeRecords?.bestSet?.value == 16 && lungeRecords?.bestDay?.value == 28)
        print("Record checks passed: actual-rep set/day bests, same-day sums, edits, manual merge, improvements, widget rows, auto-finish")
    }
}
