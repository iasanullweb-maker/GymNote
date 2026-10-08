import Foundation
import Observation

@Observable
@MainActor
final class AppModel {
    @ObservationIgnored private var replacingData = false
    @ObservationIgnored lazy var account = AccountModel(model: self)
    private(set) var selection = StoreSelection(userID: nil)
    var storageError: String?
    var data: AppData = .empty {
        didSet {
            guard !replacingData, oldValue != data else { return }
            do {
                let saved = try SharedStore.persistEdits(from: oldValue, to: data, selection: selection)
                if saved != data { replaceData(saved) }
                account.scheduleSync()
            } catch {
                replaceData(oldValue)
                storageError = "기록을 저장하지 못했어요. 원본 파일은 유지됩니다. 기기를 잠금 해제하고 다시 시도해 주세요."
            }
        }
    }
    var restStart: Date?
    var restEnd: Date?

    var todayPlan: DayPlan { data.activeWorkout?.plan ?? data.plan() }
    var workoutDate: Date { data.activeWorkout?.startedAt ?? Date() }
    var workoutProgress: (done: Int, total: Int) {
        if let session = data.activeWorkout { return (session.done, session.total) }
        return data.progress()
    }
    var savedToday: Bool { data.hasSavedWorkout() }

    func startWorkout() { data.startWorkout() }

    func finishWorkout() {
        if data.activeWorkout?.done == 0 { data.activeWorkout = nil }
        else { data.finishWorkout() }
        stopRest()
    }

    // 미리보기에서는 실제 계정 저장소를 열거나 샘플 데이터로 덮어쓰지 않음.
    init(previewData: AppData) {
        replaceData(previewData)
    }

    init() {
        do {
            selection = try SharedStore.activate(userID: nil)
            data = try SharedStore.snapshot(userID: nil).data
        } catch { storageError = "기록을 읽지 못했어요. 원본을 덮어쓰지 않고 보관합니다." }
    }

    func replaceData(_ value: AppData) {
        replacingData = true
        data = value
        replacingData = false
    }

    func switchAccount(_ userID: UUID?) async throws {
        await RestController.stop()
        restStart = nil
        restEnd = nil
        let next = try SharedStore.activate(userID: userID)
        selection = next
        replaceData(.empty)
        do { replaceData(try SharedStore.snapshot(userID: userID).data) }
        catch {
            storageError = "기록을 읽지 못했어요. 원본을 덮어쓰지 않고 보관합니다."
            throw error
        }
        storageError = nil
    }

    func reload() {
        do { replaceData(try SharedStore.snapshot(userID: selection.userID).data) }
        catch { storageError = "기록을 읽지 못했어요. 기기를 잠금 해제하고 다시 시도해 주세요." }
        // 어제 마치지 않은 운동은 일지로 정리하고 오늘 계획으로 돌아감
        if let session = data.activeWorkout, session.day != DayKey.key() {
            data.closeStaleWorkout()
        }
        if let rest = RestController.current(), rest.end > Date() {
            restStart = rest.start
            restEnd = rest.end
        } else {
            restStart = nil
            restEnd = nil
            Task { await RestController.stop() }
        }
    }

    /// 세트 완료 → 기록하고 그 운동의 휴식 타이머 시작
    func completeSet(_ exercise: Exercise) {
        guard data.activeWorkout != nil else { return }
        let date = workoutDate
        data.changeSets(exercise.id, by: 1, on: date)
        if data.activeWorkout == nil { stopRest(); return }
        let progress = workoutProgress
        guard exercise.restSeconds > 0, progress.done < progress.total else { return }
        let next = data.nextUp(on: workoutDate)
        startRest(seconds: exercise.restSeconds, title: next.title, info: next.info)
    }

    func undoSet(_ exercise: Exercise) {
        data.changeSets(exercise.id, by: -1, on: workoutDate)
    }

    func startRest(seconds: Int, title: String, info: String) {
        let now = Date()
        restStart = now
        restEnd = now.addingTimeInterval(TimeInterval(max(seconds, 5)))
        let sound = data.restSound
        let owner = selection.generation.uuidString
        Task { await RestController.start(seconds: seconds, title: title, info: info, sound: sound, generation: owner) }
    }

    func startDefaultRest() {
        let next = data.nextUp(on: workoutDate)
        startRest(seconds: data.defaultRest, title: next.title, info: next.info)
    }

    func adjustDefaultRest(by delta: Int) {
        let range = SettingsView.restRange
        data.defaultRest = min(max(data.defaultRest + delta, range.lowerBound), range.upperBound)
    }

    func stopRest() {
        restStart = nil
        restEnd = nil
        Task { await RestController.stop() }
    }

    @discardableResult
    func addRecord(_ entry: RecordEntry) -> Bool {
        data.addRecord(entry)
    }
}
