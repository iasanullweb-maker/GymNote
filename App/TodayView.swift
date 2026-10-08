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
                    if model.data.activeWorkout == nil, model.savedToday {
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
                    } else if model.data.activeWorkout == nil {
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
            .safeAreaInset(edge: .top, spacing: 0) {
                if model.data.activeWorkout != nil || model.restEnd != nil {
                    WorkoutStatusBanner(
                        startedAt: model.data.activeWorkout?.startedAt,
                        restStart: model.restStart,
                        restEnd: model.restEnd,
                        finishTitle: progress.done == 0 ? "시작 취소" : "운동 마치기",
                        onSkip: { model.stopRest() },
                        onFinish: { model.finishWorkout() }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(exercise.name) \(exercise.detail)")
                .font(.title2.bold())
                .strikethrough(finished)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 24, maximum: 24), spacing: 10)],
                      alignment: .leading, spacing: 10) {
                ForEach(0..<max(exercise.sets, 0), id: \.self) { i in
                    Circle()
                        .fill(i < done ? Color.orange : Color.secondary.opacity(0.25))
                        .frame(width: 24, height: 24)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("세트 진행")
            .accessibilityValue("\(exercise.sets)세트 중 \(done)세트 완료")

            HStack(spacing: 12) {
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.title3.weight(.semibold))
                        .frame(minWidth: 28, minHeight: 40)
                }
                .buttonStyle(.bordered)
                .disabled(done == 0)
                .accessibilityLabel("세트 완료 되돌리기")

                Button(action: onComplete) {
                    Text(finished ? "완료" : "세트 완료")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
                .disabled(finished)
            }
        }
        .padding(.vertical, 10)
    }
}

/// One pinned status area stays reachable while scrolling through exercises.
struct WorkoutStatusBanner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let startedAt: Date?
    let restStart: Date?
    let restEnd: Date?
    let finishTitle: String
    let onSkip: () -> Void
    let onFinish: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let resting = restStart != nil && restEnd.map { context.date < $0 } == true
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    status(resting: resting, at: context.date)
                    Spacer(minLength: 12)
                    actions(resting: resting)
                }
                VStack(alignment: .leading, spacing: 12) {
                    status(resting: resting, at: context.date)
                    actions(resting: resting)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((resting ? Color.orange : Color.secondary).opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: resting)
        }
    }

    private func status(resting: Bool, at now: Date) -> some View {
        HStack(spacing: 12) {
            Image(systemName: resting || startedAt == nil ? "timer" : "figure.strengthtraining.traditional")
                .font(.title2).foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(resting ? "휴식 중" : (startedAt == nil ? "휴식 완료" : "운동 중"))
                    .font(.headline)
                    .contentTransition(.opacity)
                if resting, let end = restEnd {
                    Text(RestDuration.text(seconds: RestDuration.remaining(until: end, at: now)))
                        .font(.title2.monospacedDigit()).bold()
                        .accessibilityHint("남은 휴식 시간")
                } else if let startedAt {
                    Text(startedAt, style: .timer)
                        .font(.title2.monospacedDigit()).bold()
                        .accessibilityHint("운동 경과 시간")
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func actions(resting: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { actionButtons(resting: resting) }
                .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 8) { actionButtons(resting: resting) }
        }
    }

    @ViewBuilder
    private func actionButtons(resting: Bool) -> some View {
        if resting || startedAt == nil {
            Button(resting ? "건너뛰기" : "닫기", action: onSkip)
                .buttonStyle(.borderedProminent).tint(.orange)
                .accessibilityLabel(resting ? "휴식 건너뛰기" : "휴식 완료 닫기")
        }
        if startedAt != nil {
            Button(finishTitle, action: onFinish)
                .buttonStyle(.bordered)
        }
    }
}
