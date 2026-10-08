import Foundation

@main
struct AccountChecks {
    static func main() throws {
        let date = Date()
        let exercise = Exercise(name: "푸쉬업", sets: 5, detail: "10회", restSeconds: 60)
        let entry = RecordEntry(typeID: "pushup", date: date, value: 20)
        var guest = AppData.empty
        guest.records = [entry]
        guest.scheduledPlans[DayKey.key(date)] = DayPlan(title: "게스트", exercises: [exercise])
        guest.exerciseLibrary = [exercise]
        guest.logs = [DayLog(day: DayKey.key(date), doneSets: [exercise.id.uuidString: 2])]

        var account = AppData.empty
        account.defaultRest = 45
        let own = RecordEntry(typeID: "pushup", date: date, value: 30)
        account.records = [own]
        let imported = account.importingGuest(guest)
        assert(imported.records.count == 2)
        assert(imported.records.contains(entry) && imported.records.contains(own))
        assert(imported.defaultRest == 45, "계정 설정 유지")
        assert(imported == imported.importingGuest(guest), "재가져오기 중복 방지")
        assert(imported.doneSets(exercise, on: date) == 2)
        assert(account.records == [own] && guest.records == [entry], "원본 유지")

        var differentType = guest
        differentType.recordTypes[0].unit = "kg"
        let renamed = account.importingGuest(differentType)
        assert(renamed.recordType("pushup")?.unit == "회")
        assert(renamed.recordType("guest-pushup")?.unit == "kg")
        assert(renamed.records.first { $0.id == entry.id }?.typeID == "guest-pushup")
        assert(renamed == renamed.importingGuest(differentType))

        var widget = guest
        widget.changeSets(exercise.id, by: 1, on: date)
        var appEdit = guest
        appEdit.defaultRest = 75
        let concurrent = widget.applyingEdits(from: guest, to: appEdit)
        assert(concurrent.doneSets(exercise, on: date) == 3, "설정 저장 시 위젯 체크 유지")
        assert(concurrent.defaultRest == 75)
        appEdit.changeSets(exercise.id, by: -1, on: date)
        assert(widget.applyingEdits(from: guest, to: appEdit).doneSets(exercise, on: date) == 2, "앱 되돌리기는 최신 위젯 체크에서 한 세트만 차감")
        appEdit = guest
        appEdit.changeSets(exercise.id, by: 1, on: date)
        assert(widget.applyingEdits(from: guest, to: appEdit).doneSets(exercise, on: date) == 4, "앱과 위젯의 동시 체크 둘 다 유지")
        appEdit.logs = []
        assert(widget.applyingEdits(from: guest, to: appEdit).logs.isEmpty, "정리한 날짜는 빈 로그로 남기지 않음")

        var collision = account
        var existingImport = guest.recordTypes[0]
        existingImport.id = "guest-pushup"
        existingImport.unit = "초"
        collision.recordTypes.append(existingImport)
        let collisionImport = collision.importingGuest(differentType)
        assert(collisionImport.recordType("guest-pushup")?.unit == "초")
        assert(collisionImport.recordType("guest-guest-pushup")?.unit == "kg")
        assert(collisionImport.records.first { $0.id == entry.id }?.typeID == "guest-guest-pushup")
        assert(collisionImport == collisionImport.importingGuest(differentType))

        var training = guest
        training.logs = []
        assert(training.startWorkout(at: date))
        let started = guest.applyingEdits(from: guest, to: training)
        assert(started.activeWorkout == training.activeWorkout, "운동 시작이 계정 파일에 저장")
        var appTraining = training
        var widgetTraining = training
        appTraining.changeSets(exercise.id, by: 1, on: date)
        widgetTraining.changeSets(exercise.id, by: 1, on: date)
        let mergedTraining = widgetTraining.applyingEdits(from: training, to: appTraining)
        assert(mergedTraining.activeWorkout?.done == 2, "진행 중 운동도 앱·위젯 체크 둘 다 유지")
        training = mergedTraining
        training.changeSets(exercise.id, by: 2, on: date)
        appTraining = training
        widgetTraining = training
        appTraining.changeSets(exercise.id, by: 1, on: date)
        widgetTraining.changeSets(exercise.id, by: 1, on: date)
        let finished = widgetTraining.applyingEdits(from: training, to: appTraining)
        assert(finished.activeWorkout == nil && finished.workouts.count == 1)
        assert(finished.workouts[0].done == 5, "동시 마지막 체크는 일지를 중복 저장하지 않음")
        appTraining = training
        appTraining.defaultRest = 80
        let stale = widgetTraining.applyingEdits(from: training, to: appTraining)
        assert(stale.activeWorkout == nil && stale.workouts.count == 1, "위젯이 완료한 세션을 설정 저장이 되살리지 않음")
        var removeJournal = finished
        removeJournal.workouts = []
        assert(finished.applyingEdits(from: finished, to: removeJournal).workouts.isEmpty)
        let importedJournal = account.importingGuest(finished)
        assert(importedJournal.workouts == finished.workouts)
        assert(importedJournal == importedJournal.importingGuest(finished), "운동일지 가져오기 중복 방지")
        let importedSession = account.importingGuest(mergedTraining)
        assert(importedSession.activeWorkout == mergedTraining.activeWorkout)
        var sameSessionSettings = finished
        sameSessionSettings.defaultRest = 80
        assert(finished.applyingEdits(from: finished, to: sameSessionSettings).workouts == finished.workouts)

        let stored = StoredWorkout(data: imported, serverVersion: 7, dirty: true, importedGuest: true)
        let decoded = try JSONDecoder().decode(StoredWorkout.self, from: JSONEncoder().encode(stored))
        assert(decoded.revision == stored.revision && decoded.serverVersion == 7 && decoded.dirty && decoded.importedGuest)
        assert(decoded.data == imported)
        let a = StoreSelection(userID: UUID())
        let b = StoreSelection(userID: UUID())
        assert(a.scope != b.scope && a.generation != b.generation)
        assert(StoreSelection(userID: nil).scope == "guest")
        print("Account checks passed: import, idempotency, type conflicts, widget edits, workout journals, revision roundtrip")
    }
}
