import SwiftUI

struct StarterWorkoutView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let date: Date
    @State private var equipment = WorkoutEquipment.bodyweight
    @State private var experience = WorkoutExperience.beginner
    @State private var minutes = 15
    @State private var failure: String?

    private var preview: DayPlan { StarterWorkouts.plan(equipment: equipment, experience: experience, minutes: minutes) }
    private var activeOnDate: Bool { model.data.activeWorkout?.day == DayKey.key(date) }

    var body: some View {
        NavigationStack {
            Form {
                Section("운동 조건") {
                    Picker("사용할 기구", selection: $equipment) {
                        ForEach(WorkoutEquipment.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("운동 경험", selection: $experience) {
                        ForEach(WorkoutExperience.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("가능한 시간", selection: $minutes) {
                        ForEach([15, 30, 45], id: \.self) { Text("\($0)분").tag($0) }
                    }
                }
                Section {
                    ForEach(preview.exercises) { exercise in
                        VStack(alignment: .leading, spacing: 4) {
                            ExerciseSummary(exercise: exercise)
                            if let guide = ExerciseGuides.find(exercise.name) {
                                Text("필요 기구: \(guide.equipmentText)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: { Text("기본 루틴 미리보기") } footer: {
                    Text("선택한 날짜에 추가한 뒤 세트·횟수를 편집할 수 있어요. 무게는 직접 선택하세요. 준비와 휴식에 따라 실제 시간은 달라져요.")
                }
                Section {
                    Text(date, format: .dateTime.year().month().day().weekday())
                    if !model.data.plan(for: date).isRestDay {
                        Text("기존 운동 뒤에 추가돼요.").foregroundStyle(.secondary)
                    }
                    if activeOnDate {
                        Text("이 날짜의 운동을 진행 중이에요. 마친 뒤 계획을 추가해 주세요.")
                            .foregroundStyle(.secondary)
                    }
                    if let failure { Text(failure).foregroundStyle(.red) }
                }
            }
            .navigationTitle("기본 루틴 선택").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("계획에 추가") {
                        var next = model.data
                        guard let ids = next.appendStarterWorkout(preview, on: date) else { return }
                        model.data = next
                        let savedIDs = Set(model.data.plan(for: date).exercises.map(\.id))
                        if ids.allSatisfy({ savedIDs.contains($0) }) { dismiss() }
                        else { failure = "계획을 추가하지 못했어요. 다시 시도해 주세요." }
                    }.disabled(activeOnDate)
                }
            }
        }
        .protectEditingNavigation()
    }
}
