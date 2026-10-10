import Foundation

/// 여러 기기 동기화: 마지막 동기화본(base) · 이 기기(local) · 서버 최신본(remote) 3방향 병합 검사.
@main
struct CloudMergeChecks {
    static func check(_ condition: Bool, _ message: String) {
        if !condition { fatalError("실패: \(message)") }
    }

    static func main() {
        let date = Date()
        let day = DayKey.key(date)
        let pushup = Exercise(name: "푸쉬업", sets: 3, detail: "10회", restSeconds: 60)
        let squat = Exercise(name: "스쿼트", sets: 3, detail: "15회", restSeconds: 60)
        var base = AppData.empty
        base.scheduledPlans[day] = DayPlan(title: "오늘", exercises: [pushup, squat])
        base.exerciseLibrary = [pushup, squat]
        base.defaultRest = 60

        // 1. 서로 다른 항목: 아이패드는 세트 체크, 아이폰은 설정·기록 추가 → 자동 병합
        var ipad = base
        ipad.changeSets(pushup.id, by: 2, on: date)
        var iphone = base
        iphone.defaultRest = 90
        let record = RecordEntry(typeID: "pushup", date: date, value: 25)
        iphone.records.append(record)
        check(!iphone.hasCloudConflict(local: ipad, base: base), "다른 항목 변경은 충돌 아님")
        guard let merged = iphone.mergingCloud(local: ipad, base: base) else { fatalError("병합 실패") }
        check(merged.doneSets(pushup, on: date) == 2, "이 기기의 세트 체크 유지")
        check(merged.defaultRest == 90, "다른 기기의 설정 변경 유지")
        check(merged.records == [record], "다른 기기의 기록 추가 유지")

        // 2. 양쪽 모두 기록 추가 → 둘 다 유지 (예전엔 목록 전체 교체로 한쪽이 사라짐)
        var ipadRecord = base
        let mine = RecordEntry(typeID: "pullup", date: date, value: 10)
        ipadRecord.records.append(mine)
        let both = iphone.mergingCloud(local: ipadRecord, base: base)
        check(both?.records.count == 2 && both?.records.contains(mine) == true && both?.records.contains(record) == true,
              "양쪽에서 추가한 기록 모두 유지")

        // 3. 서로 다른 운동의 세트 체크 → 둘 다 반영
        var phoneSquat = base
        phoneSquat.changeSets(squat.id, by: 1, on: date)
        let sets = phoneSquat.mergingCloud(local: ipad, base: base)
        check(sets?.doneSets(pushup, on: date) == 2 && sets?.doneSets(squat, on: date) == 1, "서로 다른 운동 체크 병합")

        // 4. 같은 운동을 같은 값으로 체크 → 한 번만 반영 (중복 합산 금지)
        var phoneSame = base
        phoneSame.changeSets(pushup.id, by: 2, on: date)
        let same = phoneSame.mergingCloud(local: ipad, base: base)
        check(same?.doneSets(pushup, on: date) == 2, "같은 체크는 두 번 세지 않음")

        // 5. 같은 운동을 다른 값으로 체크 → 사용자 선택 필요
        var phoneDifferent = base
        phoneDifferent.changeSets(pushup.id, by: 1, on: date)
        check(phoneDifferent.mergingCloud(local: ipad, base: base) == nil, "같은 운동의 다른 세트 수는 충돌")

        // 6. 같은 설정을 다르게 바꿈 → 충돌, 같게 바꿈 → 병합
        var restA = base; restA.defaultRest = 45
        var restB = base; restB.defaultRest = 120
        check(restB.mergingCloud(local: restA, base: base) == nil, "같은 설정의 다른 값은 충돌")
        restB.defaultRest = 45
        check(restB.mergingCloud(local: restA, base: base)?.defaultRest == 45, "같은 값이면 병합")

        // 7. 날짜별 계획: 다른 날짜는 병합, 같은 날짜 다른 수정은 충돌
        let tomorrow = DayKey.key(date.addingTimeInterval(86_400))
        var planA = base
        planA.scheduledPlans[tomorrow] = DayPlan(title: "내일", exercises: [squat])
        var planB = base
        planB.scheduledPlans[day]?.title = "오늘(수정)"
        let plans = planB.mergingCloud(local: planA, base: base)
        check(plans?.scheduledPlans[tomorrow]?.title == "내일" && plans?.scheduledPlans[day]?.title == "오늘(수정)", "날짜별 계획 병합")
        planA.scheduledPlans[day]?.title = "다른 수정"
        check(planB.mergingCloud(local: planA, base: base) == nil, "같은 날짜 계획의 다른 수정은 충돌")

        // 8. 진행 중 운동: 한쪽만 진행하면 병합, 양쪽이 같은 세션을 다르게 진행하면 충돌
        var training = base
        check(training.startWorkout(at: date), "운동 시작")
        var ipadTraining = training
        ipadTraining.changeSets(pushup.id, by: 1, on: date)
        var phoneSettings = training
        phoneSettings.restStep = 10
        let session = phoneSettings.mergingCloud(local: ipadTraining, base: training)
        check(session?.activeWorkout?.done == 1 && session?.restStep == 10, "한 기기에서 진행한 운동 + 다른 기기 설정")
        var phoneTraining = training
        phoneTraining.changeSets(squat.id, by: 1, on: date)
        check(phoneTraining.mergingCloud(local: ipadTraining, base: training) == nil, "같은 운동 세션을 양쪽에서 진행하면 충돌")

        // 9. 다른 기기가 운동을 마침, 이 기기는 그 사이 설정만 변경 → 마친 운동 유지
        var finishedOnPhone = ipadTraining
        check(finishedOnPhone.finishWorkout(at: date), "운동 마치기")
        var tabletRest = ipadTraining
        tabletRest.defaultRest = 75
        let finished = finishedOnPhone.mergingCloud(local: tabletRest, base: ipadTraining)
        check(finished?.activeWorkout == nil && finished?.workouts.count == 1 && finished?.defaultRest == 75,
              "다른 기기에서 마친 운동이 되살아나지 않음")

        // 10. 일상: 서로 다른 항목 추가는 병합, 같은 항목 같은 날 완료는 하나만 남김
        var dailyBase = base
        let reading = DailyItem(title: "독서")
        dailyBase.dailyItems = [reading]
        var dailyA = dailyBase
        dailyA.dailyItems.append(DailyItem(title: "물 마시기"))
        check(dailyA.markDailyComplete(reading.id, on: date), "완료 A")
        var dailyB = dailyBase
        dailyB.dailyItems.append(DailyItem(title: "스트레칭"))
        check(dailyB.markDailyComplete(reading.id, on: date), "완료 B")
        let daily = dailyB.mergingCloud(local: dailyA, base: dailyBase)
        check(daily?.dailyItems.count == 3, "양쪽 일상 항목 추가 유지")
        check(daily?.dailyCompletions.filter { $0.itemID == reading.id }.count == 1, "같은 날 같은 항목 완료는 하나만")

        // 11. 한쪽이 항목 삭제, 다른 쪽이 같은 항목 수정 → 충돌
        var deleted = dailyBase
        deleted.dailyItems = []
        var renamed = dailyBase
        renamed.dailyItems[0].title = "책 읽기"
        check(renamed.mergingCloud(local: deleted, base: dailyBase) == nil, "삭제 vs 수정은 충돌")

        // 12. 이 기기 변경이 없으면 서버 최신본 그대로
        check(iphone.mergingCloud(local: base, base: base) == iphone, "로컬 변경 없음 → 서버본")

        // 13. 목록 순서 변경은 동시 변경이 없을 때 그대로 유지 (기기 안 위젯 병합 경로)
        var reordered = base
        reordered.exerciseLibrary.reverse()
        check(base.applyingEdits(from: base, to: reordered).exerciseLibrary == reordered.exerciseLibrary, "순서 변경 저장")

        // 14. 예전 저장 파일(syncedBase 없음)도 그대로 읽힘
        let legacy = try! JSONEncoder().encode(StoredWorkout(data: base))
        var fields = try! JSONSerialization.jsonObject(with: legacy) as! [String: Any]
        fields.removeValue(forKey: "syncedBase")
        let decoded = try! JSONDecoder().decode(StoredWorkout.self, from: JSONSerialization.data(withJSONObject: fields))
        check(decoded.syncedBase == nil && decoded.data == base, "기존 저장 파일 호환")

        print("cloud merge checks passed")
    }
}
