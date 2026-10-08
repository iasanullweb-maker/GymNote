import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let plan = model.todayPlan
        let progress = model.workoutProgress
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(plan.isRestDay ? "오늘은 휴식일" : "\(progress.done) / \(progress.total) 세트")
                            .font(.headline)
                        if !plan.isRestDay {
                            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                                .tint(.orange)
                        }
                    }.padding(.vertical, 4)
                    if let session = model.data.activeWorkout {
                        HStack {
                            Label("운동 중", systemImage: "figure.strengthtraining.traditional")
                            Spacer()
                            Text(session.startedAt, style: .timer).monospacedDigit()
                            Button(progress.done == 0 ? "시작 취소" : "운동 마치기") { model.finishWorkout() }
                                .buttonStyle(.bordered)
                        }
                    } else if model.savedToday {
                        HStack {
                            Label("운동 일지에 저장됨", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Spacer()
                            Button { model.startWorkout() } label: {
                                Label("새 운동 시작", systemImage: "plus")
                            }
                            .buttonStyle(.bordered)
                            .disabled(plan.isRestDay)
                        }
                    } else {
                        Button { model.startWorkout() } label: {
                            Label("운동 시작", systemImage: "play.fill")
                        }.disabled(plan.isRestDay)
                    }
                }
                if !plan.isRestDay {
                    Section("운동") {
                        ForEach(plan.exercises) { exercise in
                            ExerciseRow(
                                exercise: exercise,
                                done: model.data.doneSets(exercise, on: model.workoutDate),
                                onComplete: { model.completeSet(exercise) },
                                onUndo: { model.undoSet(exercise) }
                            ).disabled(model.data.activeWorkout == nil)
                        }
                    }
                }
                Section {
                    if let start = model.restStart, let end = model.restEnd {
                        RestBanner(start: start, end: end) { model.stopRest() }
                    } else {
                        HStack {
                            Button { model.startDefaultRest() } label: {
                                Label("휴식 타이머 \(RestDuration.text(seconds: model.data.defaultRest))", systemImage: "timer")
                            }
                            .buttonStyle(.borderless)
                            Spacer()
                            // 기본 휴식 시간 조절 (간격은 설정 탭의 '−/+ 버튼 간격')
                            Button { model.adjustDefaultRest(by: -model.data.restStep) } label: {
                                Image(systemName: "minus")
                                    .font(.body.weight(.semibold))
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.data.defaultRest <= SettingsView.restRange.lowerBound)
                            .accessibilityLabel("휴식 시간 \(RestDuration.text(seconds: model.data.restStep)) 줄이기")
                            Button { model.adjustDefaultRest(by: model.data.restStep) } label: {
                                Image(systemName: "plus")
                                    .font(.body.weight(.semibold))
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.data.defaultRest >= SettingsView.restRange.upperBound)
                            .accessibilityLabel("휴식 시간 \(RestDuration.text(seconds: model.data.restStep)) 늘리기")
                        }
                    }
                }
            }
            .navigationTitle("\(DayKey.weekdayName(model.workoutDate))요일 · \(plan.isRestDay ? "휴식" : plan.title)")
        }
    }
}

struct ExerciseRow: View {
    let exercise: Exercise
    let done: Int
    let onComplete: () -> Void
    let onUndo: () -> Void

    private var finished: Bool { done >= exercise.sets }

    private var subtitle: String { "\(exercise.sets)세트 · \(exercise.detail)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.headline)
                        .strikethrough(finished)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(done)/\(exercise.sets)")
                    .font(.title3.monospacedDigit())
                    .bold()
                    .foregroundStyle(finished ? Color.green : Color.primary)
            }

            HStack(spacing: 6) {
                ForEach(0..<max(exercise.sets, 0), id: \.self) { i in
                    Circle()
                        .fill(i < done ? Color.orange : Color.secondary.opacity(0.25))
                        .frame(width: 12, height: 12)
                }
                Spacer()
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .disabled(done == 0)

                Button(action: onComplete) {
                    Text(finished ? "완료" : "세트 완료")
                }
                .buttonStyle(.borderedProminent)
                .disabled(finished)
            }
        }
        .padding(.vertical, 4)
    }
}

struct RestBanner: View {
    let start: Date
    let end: Date
    let onStop: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let resting = context.date < end
            HStack(spacing: 12) {
                Image(systemName: resting ? "timer" : "bell.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text(resting ? "휴식 중" : "휴식 끝! 다음 세트")
                    .font(.headline)
                Spacer()
                if resting {
                    Text(RestDuration.text(seconds: RestDuration.remaining(until: end, at: context.date)))
                        .font(.title.monospacedDigit())
                        .bold()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(minWidth: 100, alignment: .trailing)
                }
                Button(resting ? "건너뛰기" : "닫기", action: onStop)
                    .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)
        }
    }
}
