import Foundation
import Observation

@Observable
final class AppModel {
    var data: AppData = SharedStore.load()
    var restStart: Date?
    var restEnd: Date?

    var todayPlan: DayPlan { data.plan() }

    func reload() {
        data = SharedStore.load()
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
        Task { await RestController.start(seconds: seconds, title: title, info: info) }
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
