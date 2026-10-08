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

        let stored = StoredWorkout(data: imported, serverVersion: 7, dirty: true, importedGuest: true)
        let decoded = try JSONDecoder().decode(StoredWorkout.self, from: JSONEncoder().encode(stored))
        assert(decoded.revision == stored.revision && decoded.serverVersion == 7 && decoded.dirty && decoded.importedGuest)
        assert(decoded.data == imported)
        let a = StoreSelection(userID: UUID())
        let b = StoreSelection(userID: UUID())
        assert(a.scope != b.scope && a.generation != b.generation)
        assert(StoreSelection(userID: nil).scope == "guest")
        print("Account checks passed: import, idempotency, type conflicts, widget edits, revision roundtrip")
    }
}
