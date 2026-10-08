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

    var todayPlan: DayPlan { data.plan() }

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
        data.changeSets(exercise.id, by: 1)
        let progress = data.progress()
        guard exercise.restSeconds > 0, progress.done < progress.total else { return }
        let next = data.nextUp()
        startRest(seconds: exercise.restSeconds, title: next.title, info: next.info)
    }

    func undoSet(_ exercise: Exercise) {
        data.changeSets(exercise.id, by: -1)
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
        let next = data.nextUp()
        startRest(seconds: data.defaultRest, title: next.title, info: next.info)
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
