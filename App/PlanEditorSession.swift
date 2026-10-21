import Foundation
import Observation

/// A date editor belongs to the store generation it was opened for.
@Observable
@MainActor
final class PlanEditorSession {
    let date: Date
    private let model: AppModel
    private let owner: UUID
    var failure: String?
    private(set) var deletion: PlannedExerciseDeletion?

    init(model: AppModel, date: Date) {
        self.model = model
        self.date = date
        owner = model.selection.generation
    }

    var plan: DayPlan { model.data.plan(for: date) }
    var canUndo: Bool {
        owner == model.selection.generation && deletion.map { model.data.canRestorePlannedExercise($0) } == true
    }

    @discardableResult
    func save(_ edit: (inout AppData) -> Void) -> Bool {
        guard owner == model.selection.generation else {
            failure = "계정이 바뀌었어요. 이 화면을 닫고 다시 열어 주세요."
            return false
        }
        guard model.data.activeWorkout?.day != DayKey.key(date) else {
            failure = "진행 중인 운동을 마친 뒤 계획을 수정해 주세요."
            return false
        }
        guard model.saveEdit(edit) else {
            failure = "저장하지 못했어요. 변경 전 계획은 그대로예요. 다시 시도해 주세요."
            return false
        }
        failure = nil
        deletion = nil
        return true
    }

    func rename(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return save { data in
            var plan = data.plan(for: date)
            plan.title = trimmed.isEmpty ? DayPlan(title: "", exercises: plan.exercises).displayTitle : trimmed
            data.scheduledPlans[DayKey.key(date)] = plan
        }
    }

    func add(_ exercise: Exercise) -> Bool {
        save { data in
            var plan = data.plan(for: date)
            if plan.isRestDay && (plan.title == "휴식" || plan.title.isEmpty) { plan.title = exercise.name }
            plan.exercises.append(exercise)
            data.scheduledPlans[DayKey.key(date)] = plan
        }
    }

    func remove(_ exercise: Exercise) {
        var token: PlannedExerciseDeletion?
        if save({ token = $0.removePlannedExercise(exercise.id, on: date) }) {
            deletion = token
        }
    }

    func undoDeletion() {
        guard let token = deletion, canUndo else {
            failure = "계획이 바뀌어 이 삭제를 되돌릴 수 없어요."
            return
        }
        save { _ = $0.restorePlannedExercise(token) }
    }

    func move(from source: IndexSet, to destination: Int) {
        save { data in
            var plan = data.plan(for: date)
            let indexes = source.sorted().filter { plan.exercises.indices.contains($0) }
            let moving = indexes.map { plan.exercises[$0] }
            for index in indexes.reversed() { plan.exercises.remove(at: index) }
            let insertion = min(max(0, destination - indexes.filter { $0 < destination }.count), plan.exercises.count)
            plan.exercises.insert(contentsOf: moving, at: insertion)
            data.scheduledPlans[DayKey.key(date)] = plan
        }
    }

    func replace(with source: DayPlan) -> Bool {
        guard !source.isRestDay else {
            failure = "가져올 운동이 없는 휴식 계획이에요."
            return false
        }
        return save { data in _ = data.replacePlannedWorkout(with: source, on: date) }
    }
}
