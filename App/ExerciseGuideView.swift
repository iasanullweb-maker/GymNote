import SwiftUI

struct ExerciseGuideRequest: Identifiable {
    let exercise: Exercise
    let date: Date
    let sessionID: UUID?
    let done: Int
    let owner: UUID
    var id: UUID { exercise.id }
}

struct ExerciseGuideView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: ExerciseGuideRequest
    @State private var reason = ReplacementReason.busy
    @State private var equipment: WorkoutEquipment?
    @State private var selected: ExerciseGuide?
    @State private var detail = "8회"
    @State private var failure: String?

    private var guide: ExerciseGuide? { ExerciseGuides.find(request.exercise.name) }
    private var remaining: Int { max(0, request.exercise.sets - request.done) }
    private var candidates: [ExerciseGuide] {
        ExerciseGuides.alternatives(for: request.exercise.name, equipment: equipment, reason: reason)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let guide {
                    Section("운동 안내") {
                        LabeledContent("주요 부위", value: guide.focus)
                        LabeledContent("필요 기구", value: guide.equipmentText)
                        ForEach(guide.cues, id: \.self) { Text($0) }
                        Text(guide.mistake).foregroundStyle(.secondary)
                        if let url = URL(string: guide.source) {
                            Link("자세 자료 보기 (외부 사이트)", destination: url)
                        }
                    }
                } else {
                    Section("운동 안내") { Text("이 종목의 안내는 아직 준비되지 않았어요.") }
                }
                if remaining > 0 {
                    Section {
                        Picker("바꾸려는 이유", selection: $reason) {
                            ForEach(ReplacementReason.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Picker("사용 가능한 기구", selection: $equipment) {
                            Text("전체 보기").tag(Optional<WorkoutEquipment>.none)
                            ForEach(WorkoutEquipment.allCases) { Text($0.rawValue).tag(Optional($0)) }
                        }
                        ForEach(candidates) { candidate in candidateButton(candidate) }
                        if candidates.isEmpty {
                            Text("이 조건에 맞는 대체 후보가 없어요.").foregroundStyle(.secondary)
                        }
                        DisclosureGroup("전체 안내 종목에서 직접 선택") {
                            ForEach(ExerciseGuides.all.filter { $0.id != guide?.id }) { candidate in
                                candidateButton(candidate)
                            }
                        }
                    } header: { Text("남은 \(remaining)세트 바꾸기") } footer: {
                        Text("후보는 비슷한 동작을 기준으로 골랐어요. 필요한 기구와 목표를 확인하세요. 이미 완료한 \(request.done)세트는 원래 운동 기록으로 남아요.")
                    }
                    if let selected {
                        Section("바꿀 운동 확인") {
                            Text(selected.name).font(.headline)
                            Text("\(remaining)세트 · \(selected.equipmentText)")
                            TextField("횟수·시간 (예: 8회, 20초)", text: $detail)
                            ForEach(selected.cues, id: \.self) { Text($0).font(.subheadline) }
                            Button("남은 세트를 이 운동으로 바꾸기") { apply(selected) }
                                .disabled(detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                          || detail.contains("%") || detail.contains("％"))
                        }
                    }
                    if let failure { Section { Text(failure).foregroundStyle(.red) } }
                }
            }
            .navigationTitle(request.exercise.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
            .onChange(of: reason) { _, _ in selected = nil }
            .onChange(of: equipment) { _, _ in selected = nil }
        }
        .protectEditingNavigation()
    }

    private func candidateButton(_ candidate: ExerciseGuide) -> some View {
        Button {
            selected = candidate
            detail = candidate.defaultDetail
            failure = nil
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.name)
                Text("\(candidate.focus) · \(candidate.equipmentText)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func apply(_ selected: ExerciseGuide) {
        guard model.selection.generation == request.owner else {
            failure = "계정이 바뀌었어요. 닫은 뒤 다시 선택해 주세요."
            return
        }
        let replacement = Exercise(name: selected.name, sets: remaining,
                                   detail: detail.trimmingCharacters(in: .whitespacesAndNewlines))
        var next = model.data
        guard let id = next.replaceExecutionExercise(request.exercise, with: replacement, on: request.date,
                                                     expectedSessionID: request.sessionID, expectedDone: request.done) else {
            failure = "운동 상태가 바뀌었어요. 닫은 뒤 현재 세트를 확인하고 다시 선택해 주세요."
            return
        }
        let persisted = model.saveEdit { $0 = next }
        if !persisted { model.reload() }
        let plan = model.data.activeWorkout?.plan ?? model.data.plan(for: request.date)
        if persisted && plan.exercises.contains(where: { $0.id == id }) { dismiss() }
        else { failure = "변경을 저장하지 못했어요. 다시 시도해 주세요." }
    }
}
