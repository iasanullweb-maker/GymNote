import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    @Environment(\.gymnoteCompactLayout) private var compact
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var recordingType: RecordType?
    /// 기록 입력 시트가 닫힌 뒤에 보여 줄 결과(시트와 알림이 겹쳐 알림이 사라지지 않게).
    @State private var pendingRecordResult: (result: AppModel.RecordSaveResult, text: String)?
    @State private var savedRecordText: String?

    private var orderAnimation: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.25) }

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
                        (compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())) {
                            Label("운동 일지에 저장됨", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            if !compact { Spacer() }
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
                    let date = model.workoutDate
                    Section {
                        // 길게 눌러 끌기는 List 기본 순서 바꾸기(onMove)를 쓴다: 위·아래·맨 끝 이동, 끌기 취소,
                        // 앱 밖 텍스트 끌어 놓기 거부가 시스템 동작으로 처리되고, 놓았을 때 한 번만 저장한다.
                        ForEach(model.data.executionExercises(on: date)) { exercise in
                            ExerciseRow(
                                exercise: exercise,
                                done: model.data.doneSets(exercise, on: date),
                                session: model.data.activeWorkout,
                                onComplete: { reps in
                                    withAnimation(orderAnimation) { model.completeSet(exercise, actualReps: reps) }
                                },
                                onUndo: { withAnimation(orderAnimation) { model.undoSet(exercise) } },
                                availableMoves: ExecutionMove.allCases.filter {
                                    model.data.canMoveExecutionExercise(exercise.id, $0, on: date)
                                },
                                onMove: { move in
                                    withAnimation(orderAnimation) { model.moveExecutionExercise(exercise.id, move) }
                                }
                            )
                            .id("\(model.data.activeWorkout?.id.uuidString ?? "idle")-\(exercise.id)")
                        }
                        .onMove { source, destination in
                            withAnimation(orderAnimation) {
                                model.moveExecutionExercises(fromOffsets: source, toOffset: destination)
                            }
                        }
                    } header: {
                        Text("운동")
                    } footer: {
                        Text("운동을 길게 눌러 끌면 순서를 바꿀 수 있어요. 완료한 운동은 아래에 모이고, 완료를 취소하면 원래 자리로 돌아가요.")
                    }
                }
                Section {
                    let types = account.catalogTypes.filter(\.active)
                    Menu {
                        ForEach(types) { type in
                            Button {
                                recordingType = type.recordType
                            } label: {
                                Label(type.name, systemImage: type.recordType.style == .rounds ? "repeat" : "number")
                            }
                        }
                    } label: {
                        Label("종목 기록 남기기", systemImage: "square.and.pencil")
                    }
                    .disabled(types.isEmpty)
                    .accessibilityHint("공통 종목을 골라 횟수·라운드·무게·시간 기록을 입력")
                } header: {
                    Text("종목 기록")
                } footer: {
                    Text(account.catalogTypes.contains(where: \.active)
                         ? "횟수·라운드·무게 등의 기록을 남기면 최고 기록에 반영돼요."
                         : "공통 종목 목록을 불러오면 기록을 남길 수 있어요.")
                }
                Section {
                    (compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())) {
                        Button { model.startDefaultRest() } label: {
                            Label("휴식 타이머 \(RestDuration.text(seconds: model.data.defaultRest))", systemImage: "timer")
                        }
                        .buttonStyle(.borderless)
                        HStack {
                            if !compact { Spacer() }
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
            .navigationBarTitleDisplayMode(compact ? .inline : .large)
            // 공통 종목 갱신은 RootView가 앱 활성 중 60초마다 한다(탭을 오갈 때마다 다시 요청하지 않음).
            .sheet(item: $recordingType, onDismiss: showRecordResult) { type in
                AddRecordView(types: account.catalogTypes.filter(\.active).map(\.recordType), fixedTypeID: type.id) { entry in
                    let result = model.saveRecord(entry)
                    if result != .rejected { pendingRecordResult = (result, "\(type.name) \(type.display(entry))") }
                    return result != .rejected
                }
            }
            .alert("기록을 저장했어요", isPresented: Binding(
                get: { savedRecordText != nil },
                set: { if !$0 { savedRecordText = nil } }
            )) {
                Button("확인") { savedRecordText = nil }
            } message: {
                Text((savedRecordText ?? "") + "\n운동 기록에 남겼어요. 최고 기록은 그대로예요.")
            }
            .alert("🎉 신기록!", isPresented: Binding(
                get: { model.recordMessage != nil },
                set: { if !$0 { model.recordMessage = nil } }
            )) {
                Button("확인") { model.recordMessage = nil }
            } message: {
                Text((model.recordMessage ?? "") + "\n기록 탭의 최고 기록에 자동으로 반영했어요.")
            }
        }
    }
}

extension TodayView {
    private func showRecordResult() {
        guard let pending = pendingRecordResult else { return }
        pendingRecordResult = nil
        if pending.result == .newBest { model.recordMessage = pending.text }
        else { savedRecordText = pending.text }
    }
}

extension ExecutionMove {
    var accessibilityName: String {
        switch self {
        case .up: "위로 이동"
        case .down: "아래로 이동"
        case .top: "맨 위로 이동"
        case .bottom: "맨 아래로 이동"
        }
    }
}

struct ExerciseRow: View {
    @Environment(\.gymnoteCompactLayout) private var compact
    @Environment(\.dynamicTypeSize) private var textSize
    let exercise: Exercise
    let done: Int
    let session: WorkoutSession?
    let onComplete: (Int?) -> Void
    let onUndo: () -> Void
    /// 접근성 순서 바꾸기(같은 완료 묶음 안). 끌기와 같은 규칙으로 저장된다.
    var availableMoves: [ExecutionMove] = []
    var onMove: (ExecutionMove) -> Void = { _ in }
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
                .accessibilityAddTraits(.isHeader)
                .accessibilityValue(finished ? "완료" : "")
                .accessibilityActions {
                    ForEach(availableMoves, id: \.self) { move in
                        Button(move.accessibilityName) { onMove(move) }
                    }
                }

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
                (compact || textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 16))) {
                    Text("실제 횟수").font(.headline)
                    if !compact && !textSize.isAccessibilitySize { Spacer(minLength: 0) }
                    HStack(spacing: 12) {
                        Button { draftReps = max(0, value - 1) } label: {
                            Image(systemName: "minus").frame(width: 32, height: 36)
                        }
                        .buttonStyle(.bordered).disabled(session == nil || value == 0)
                        .accessibilityLabel("실제 횟수 1회 줄이기")
                        Button { editingReps = true } label: {
                            Text("\(value)회").font(.title2.bold().monospacedDigit())
                                .frame(minWidth: 64, minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                        .disabled(session == nil)
                        .accessibilityLabel("실제 횟수 \(value)회, 직접 입력")
                        Button { draftReps = min(9999, value + 1) } label: {
                            Image(systemName: "plus").frame(width: 32, height: 36)
                        }
                        .buttonStyle(.bordered).disabled(session == nil || value == 9999)
                        .accessibilityLabel("실제 횟수 1회 늘리기")
                    }
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
                .disabled(session == nil || done == 0)
                .accessibilityLabel("세트 완료 되돌리기")

                Button { onComplete(actualReps) } label: {
                    Text(finished ? "완료" : actualReps.map { "\($0)회로 세트 완료" } ?? "세트 완료")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
                .disabled(session == nil || finished)
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
        .protectEditingNavigation()
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

/// 운동 중·휴식 상태. RootView가 각 탭 콘텐츠의 하단 safeAreaInset에 놓으므로 탭 막대·목록의 마지막 버튼을
/// 가리지 않는다. 가로 iPhone처럼 세로 공간이 좁으면 줄 수와 여백을 줄인다.
struct WorkoutStatusBanner: View {
    @Environment(\.gymnoteCompactLayout) private var compact
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let startedAt: Date?
    let restStart: Date?
    let restEnd: Date?
    let finishTitle: String
    let onSkip: () -> Void
    let onFinish: () -> Void
    var doneSets = 0
    var totalSets = 0

    private var tight: Bool { compact || verticalSizeClass == .compact }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let resting = restStart != nil && restEnd.map { context.date < $0 } == true
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    status(resting: resting, at: context.date)
                    Spacer(minLength: 12)
                    actions(resting: resting)
                }
                VStack(alignment: .leading, spacing: tight ? 8 : 12) {
                    status(resting: resting, at: context.date)
                    actions(resting: resting)
                }
            }
            .padding(tight ? 10 : 16)
            .frame(maxWidth: 720, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.orange.opacity(resting ? 0.5 : 0.25), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: resting)
        }
    }

    private func status(resting: Bool, at now: Date) -> some View {
        HStack(spacing: 12) {
            Image(systemName: resting || startedAt == nil ? "timer" : "figure.strengthtraining.traditional")
                .font(.title2).foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: tight ? 2 : 4) {
                Text(resting ? "휴식 중" : (startedAt == nil ? "휴식 완료" : "운동 중"))
                    .font(.headline)
                    .contentTransition(.opacity)
                // 시간과 세트 수를 한 줄에 둬서 높이를 줄인다. 큰 글자에서 넘치면 두 줄로.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) { clock(resting: resting, at: now); setCount }
                    VStack(alignment: .leading, spacing: 2) { clock(resting: resting, at: now); setCount }
                }
                if startedAt != nil, totalSets > 0 {
                    ProgressView(value: Double(min(doneSets, totalSets)), total: Double(max(totalSets, 1)))
                        .tint(.orange)
                        .accessibilityLabel("세트 진행도")
                        .accessibilityValue("\(totalSets)세트 중 \(doneSets)세트 완료")
                }
            }
        }
        .frame(minWidth: 100, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func clock(resting: Bool, at now: Date) -> some View {
        if resting, let end = restEnd {
            Text(RestDuration.text(seconds: RestDuration.remaining(until: end, at: now)))
                .font(tight ? .headline.monospacedDigit() : .title2.monospacedDigit()).bold()
                .accessibilityHint("남은 휴식 시간")
        } else if let startedAt {
            Text(startedAt, style: .timer)
                .font(tight ? .headline.monospacedDigit() : .title2.monospacedDigit()).bold()
                .accessibilityHint("운동 경과 시간")
        }
    }

    @ViewBuilder
    private var setCount: some View {
        if startedAt != nil, totalSets > 0 {
            Text("\(doneSets) / \(totalSets) 세트")
                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                .accessibilityHidden(true) // 진행도 막대가 같은 값을 읽어 준다.
        }
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

/// 운동 마치기 후 표시: 운동 중 → 운동 완료 → 운동 일지에 저장됨.
/// AppModel.savedWorkout(실제 저장 성공)이 있을 때만 보이며, 상태 배너와 같은 자리·모양이라 화면이 튀지 않는다.
struct WorkoutCompletionBanner: View {
    @Environment(\.gymnoteCompactLayout) private var compact
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let session: WorkoutSession
    /// 0 운동 중, 1 운동 완료, 2 운동 일지에 저장됨
    let phase: Int

    private var tight: Bool { compact || verticalSizeClass == .compact }
    private var title: String { ["운동 중", "운동 완료", "운동 일지에 저장됨"][min(max(phase, 0), 2)] }
    private var icon: String {
        ["figure.strengthtraining.traditional", "checkmark.circle.fill", "book.closed.fill"][min(max(phase, 0), 2)]
    }
    private var minutes: Int? {
        session.endedAt.map { max(0, Int($0.timeIntervalSince(session.startedAt) / 60)) }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2).foregroundStyle(phase == 0 ? Color.orange : Color.green)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: tight ? 2 : 4) {
                Text(title).font(.headline).contentTransition(.opacity)
                Text("\(session.done) / \(session.total) 세트" + (minutes.map { " · \($0)분" } ?? ""))
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                ProgressView(value: Double(min(session.done, session.total)), total: Double(max(session.total, 1)))
                    .tint(phase == 0 ? .orange : .green)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
        }
        .padding(tight ? 10 : 16)
        .frame(maxWidth: 720, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder((phase == 0 ? Color.orange : Color.green).opacity(0.4), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
    }
}
