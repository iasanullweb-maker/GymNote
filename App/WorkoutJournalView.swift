import SwiftUI

struct WorkoutJournalView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            ForEach(model.data.workouts.sorted { $0.startedAt > $1.startedAt }) { workout in
                NavigationLink {
                    WorkoutJournalDetail(workout: workout)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(workout.plan.title).font(.headline)
                            Spacer()
                            Text("\(workout.done)세트").foregroundStyle(.secondary)
                        }
                        Text(workout.startedAt, format: .dateTime.year().month().day())
                            .font(.caption).foregroundStyle(.secondary)
                        Text(workout.plan.exercises.filter { workout.doneSets($0) > 0 }.map(\.name).joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .swipeActions {
                    Button("삭제", role: .destructive) {
                        model.data.workouts.removeAll { $0.id == workout.id }
                    }
                }
            }
        }
        .overlay {
            if model.data.workouts.isEmpty {
                ContentUnavailableView("아직 운동 일지가 없어", systemImage: "figure.strengthtraining.traditional", description: Text("운동 탭에서 시작하고 세트를 완료하면 자동으로 저장돼."))
            }
        }
    }
}

struct WorkoutJournalDetail: View {
    let workout: WorkoutSession

    var body: some View {
        List {
            Section("운동 요약") {
                LabeledContent("날짜", value: workout.startedAt.formatted(.dateTime.year().month().day()))
                LabeledContent("완료 세트", value: "\(workout.done) / \(workout.total)")
                if let end = workout.endedAt {
                    LabeledContent("운동 시간", value: "\(Int(end.timeIntervalSince(workout.startedAt)) / 60)분")
                }
            }
            Section {
                ForEach(workout.plan.exercises) { exercise in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name).font(.headline)
                            Text("세트당 \(exercise.detail)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(workout.doneSets(exercise)) / \(exercise.sets)세트")
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("운동별 기록")
            } footer: {
                Text("횟수·시간은 운동 시작 당시 계획에 적힌 세트당 기준이야. 이후 계획을 바꿔도 이 일지는 유지돼.")
            }
        }
        .navigationTitle(workout.plan.title)
    }
}
