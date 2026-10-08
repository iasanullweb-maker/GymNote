import Foundation
import Observation

@Observable
final class AppModel {
    var data: AppData = SharedStore.load()
    var restStart: Date?
    var restEnd: Date?

    var todayPlan: DayPlan { data.activeWorkout?.plan ?? data.plan() }
    var workoutDate: Date { data.activeWorkout?.startedAt ?? Date() }
    var workoutProgress: (done: Int, total: Int) {
        if let session = data.activeWorkout { return (session.done, session.total) }
        return data.progress()
    }
    var savedToday: Bool { data.workouts.contains { $0.day == DayKey.key() } }

    func startWorkout() { data.startWorkout() }

    func finishWorkout() {
        if data.activeWorkout?.done == 0 { data.activeWorkout = nil }
        else { data.finishWorkout() }
        stopRest()
    }

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
        Task { await RestController.start(seconds: seconds, title: title, info: info, sound: sound) }
    }

    func startDefaultRest() {
        let next = data.nextUp(on: workoutDate)
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
