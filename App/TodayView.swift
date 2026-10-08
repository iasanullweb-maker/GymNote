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
                                session: model.data.activeWorkout,
                                onComplete: { model.completeSet(exercise, actualReps: $0) },
                                onUndo: { model.undoSet(exercise) }
                            ).disabled(model.data.activeWorkout == nil)
                                .id("\(model.data.activeWorkout?.id.uuidString ?? "idle")-\(exercise.id)")
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
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("\(DayKey.weekdayName(model.workoutDate))요일 · \(plan.isRestDay ? "휴식" : plan.title)")
        }
    }
}

struct ExerciseRow: View {
    let exercise: Exercise
    let done: Int
    let session: WorkoutSession?
    let onComplete: (Int?) -> Void
    let onUndo: () -> Void
    @State private var draftReps: Int?
    @State private var editingReps = false

    private var finished: Bool { done >= exercise.sets }
    private var actualReps: Int? { draftReps ?? exercise.plannedReps }

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

            if !finished, let value = actualReps {
                Text("\(done + 1)세트 · 계획 \(exercise.detail)")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    Text("실제 횟수").font(.headline)
                    Spacer(minLength: 0)
                    Button { draftReps = max(0, value - 1) } label: {
                        Image(systemName: "minus").frame(width: 32, height: 36)
                    }
                    .buttonStyle(.bordered).disabled(value == 0)
                    .accessibilityLabel("실제 횟수 1회 줄이기")
                    Button { editingReps = true } label: {
                        Text("\(value)회").font(.title2.bold().monospacedDigit())
                            .frame(minWidth: 64, minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("실제 횟수 \(value)회, 직접 입력")
                    Button { draftReps = min(9999, value + 1) } label: {
                        Image(systemName: "plus").frame(width: 32, height: 36)
                    }
                    .buttonStyle(.bordered).disabled(value == 9999)
                    .accessibilityLabel("실제 횟수 1회 늘리기")
                }
            }
            if let session, done > 0 {
                CompletedRepetitionRows(session: session, exercise: exercise)
            }

            HStack(spacing: 12) {
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.title3.weight(.semibold))
                        .frame(minWidth: 28, minHeight: 40)
                }
                .buttonStyle(.bordered)
                .disabled(done == 0)
                .accessibilityLabel("세트 완료 되돌리기")

                Button { onComplete(actualReps) } label: {
                    Text(finished ? "완료" : actualReps.map { "\($0)회로 세트 완료" } ?? "세트 완료")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
                .disabled(finished)
            }
        }
        .padding(.vertical, 10)
        .onChange(of: done) { _, _ in draftReps = nil }
        .onChange(of: exercise.detail) { _, _ in draftReps = nil }
        .sheet(isPresented: $editingReps) {
            RepetitionEditor(title: "\(done + 1)세트 실제 횟수", initialValue: actualReps ?? 0) {
                draftReps = $0
            }
        }
    }
}

struct RepetitionEditor: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let onSave: (Int) -> Void
    @State private var input: String
    @FocusState private var focused: Bool

    init(title: String, initialValue: Int, onSave: @escaping (Int) -> Void) {
        self.title = title
        self.onSave = onSave
        _input = State(initialValue: String(initialValue))
    }

    private var value: Int? {
        guard let number = Int(input), (0...9999).contains(number) else { return nil }
        return number
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("실제 횟수", text: $input)
                        .keyboardType(.numberPad).focused($focused)
                        .accessibilityLabel("실제 횟수")
                } footer: { Text("0~9999회까지 입력할 수 있어요. 계획 횟수는 바뀌지 않아요.") }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        if let value { onSave(value); dismiss() }
                    }.disabled(value == nil)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }
}

struct CompletedRepetitionRows: View {
    @Environment(AppModel.self) private var model
    let session: WorkoutSession
    let exercise: Exercise
    @State private var editingSet: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<session.doneSets(exercise), id: \.self) { index in
                let actual = session.repetitions(exercise, set: index)
                let weights = session.actualWeights[exercise.id.uuidString] ?? []
                let weight = index < weights.count ? weights[index] : nil
                if exercise.plannedReps != nil || actual != nil {
                    Button { editingSet = index } label: {
                        HStack {
                            Text("\(index + 1)세트")
                            Spacer()
                            if let actual, let planned = exercise.plannedReps {
                                Text("\(actual) / \(planned)회")
                            } else if let actual {
                                Text("\(actual)회")
                            } else {
                                Text("횟수 미기록")
                            }
                            Image(systemName: "pencil").accessibilityHidden(true)
                        }.font(.subheadline).monospacedDigit()
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHint("눌러서 실제 횟수 수정")
                } else {
                    HStack {
                        Text("\(index + 1)세트")
                        Spacer()
                        Text(exercise.detail)
                    }.font(.subheadline).foregroundStyle(.secondary)
                }
                if let weight {
                    Text("무게 \(RecordType.number(weight))kg")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: Binding(get: { editingSet != nil }, set: { if !$0 { editingSet = nil } })) {
            if let index = editingSet {
                RepetitionEditor(title: "\(index + 1)세트 실제 횟수",
                                 initialValue: session.repetitions(exercise, set: index) ?? exercise.plannedReps ?? 0) {
                    model.data.updateRepetitions(sessionID: session.id, exerciseID: exercise.id, set: index, value: $0)
                }
            }
        }
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
