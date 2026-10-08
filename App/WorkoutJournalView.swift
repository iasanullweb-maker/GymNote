import SwiftUI

struct WorkoutJournalView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedDate = Date()
    @State private var showingCalendar = true

    var body: some View {
        List {
            Section {
                Picker("일지 보기", selection: $showingCalendar) {
                    Text("캘린더").tag(true)
                    Text("전체 목록").tag(false)
                }.pickerStyle(.segmented)
                if showingCalendar {
                    PlanCalendarView(selectedDate: $selectedDate, content: .journal)
                        .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 8))
                }
            }
            Section {
                let workouts = showingCalendar ? model.data.workouts(on: selectedDate)
                    : model.data.workouts.sorted { $0.startedAt > $1.startedAt }
                if workouts.isEmpty {
                    Text(showingCalendar ? "이 날짜에는 운동 일지가 없어." : "아직 운동 일지가 없어.")
                        .foregroundStyle(.secondary)
                    if model.data.workouts.isEmpty {
                        Text("운동 탭에서 시작하고 세트를 완료하면 자동으로 저장돼.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                ForEach(workouts) { workout in
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
            } header: {
                Text(showingCalendar ? selectedDate.formatted(.dateTime.year().month().day().weekday()) : "전체 운동 일지")
            }
        }
    }
}

#Preview("운동 일지 캘린더") {
    NavigationStack { WorkoutJournalView() }
        .environment(AppModel(previewData: AppData.sample))
}

struct WorkoutJournalDetail: View {
    @Environment(AppModel.self) private var model
    private let original: WorkoutSession
    init(workout: WorkoutSession) { original = workout }
    private var workout: WorkoutSession { model.data.workouts.first { $0.id == original.id } ?? original }

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
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.name).font(.headline)
                                Text("세트당 \(exercise.detail)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(workout.doneSets(exercise)) / \(exercise.sets)세트")
                                .monospacedDigit()
                        }
                        CompletedRepetitionRows(session: workout, exercise: exercise)
                    }
                }
            } header: {
                Text("운동별 기록")
            } footer: {
                Text("횟수는 실제 / 계획 순서예요. 세트를 누르면 실제 횟수를 수정할 수 있어요. 예전 일지의 미기록 횟수와 시간은 계획 기준만 남아 있어요.")
            }
        }
        .navigationTitle(workout.plan.title)
    }
}
