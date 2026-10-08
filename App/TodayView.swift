import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let plan = model.todayPlan
        let progress = model.data.progress()

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
                    }
                    .padding(.vertical, 4)
                }

                if !plan.isRestDay {
                    Section("운동") {
                        ForEach(plan.exercises) { exercise in
                            ExerciseRow(
                                exercise: exercise,
                                done: model.data.doneSets(exercise),
                                onComplete: { model.completeSet(exercise) },
                                onUndo: { model.undoSet(exercise) }
                            )
                        }
                    }
                }

                Section {
                    if let start = model.restStart, let end = model.restEnd {
                        RestBanner(start: start, end: end) { model.stopRest() }
                    } else {
                        Button {
                            model.startDefaultRest()
                        } label: {
                            Label("휴식 타이머 \(model.data.defaultRest)초", systemImage: "timer")
                        }
                    }
                }
            }
            .navigationTitle("\(DayKey.weekdayName())요일 · \(plan.isRestDay ? "휴식" : plan.title)")
        }
    }
}

struct ExerciseRow: View {
    let exercise: Exercise
    let done: Int
    let onComplete: () -> Void
    let onUndo: () -> Void

    private var finished: Bool { done >= exercise.sets }

    private var subtitle: String {
        var text = "\(exercise.sets)세트 · \(exercise.detail)"
        if exercise.restSeconds > 0 { text += " · 휴식 \(exercise.restSeconds)초" }
        return text
    }

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
                    Text(timerInterval: start...end, countsDown: true)
                        .font(.title.monospacedDigit())
                        .bold()
                        .frame(minWidth: 80, alignment: .trailing)
                }
                Button(resting ? "건너뛰기" : "닫기", action: onStop)
                    .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)
        }
    }
}
