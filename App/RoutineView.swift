import SwiftUI

struct RoutineView: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedDate: Date
    @State private var confirmingRepeat = false
    @State private var calendarDay: PlanningDay?
    @AppStorage("planShowWorkoutAndDaily") private var showAll = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            CalendarScrollView {
                CalendarSection("캘린더") {
                    NavigationLink {
                        ScheduledDayEditor(date: selectedDate)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Label("선택한 날짜 계획 설정", systemImage: "calendar.badge.plus")
                                Text(selectedDate, format: .dateTime.year().month().day().weekday())
                                    .font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                    .coachmarkTarget("workout.plan")
                    Divider()
                    Toggle("운동·일상 함께 보기", isOn: $showAll)
                    PlanCalendarView(selectedDate: $selectedDate, content: showAll ? .all : .workout) {
                        calendarDay = PlanningDay(date: $0)
                    }
                }
                if showAll {
                    TogetherPlanDaySection(date: selectedDate)
                    UndatedDailyPlanSection()
                }
                CalendarSection(showAll ? "선택한 주의 운동·일상" : "선택한 주의 운동") {
                    if showAll {
                        TogetherPlanWeekRows(selectedDate: $selectedDate)
                    } else {
                        ForEach(DayKey.weekDates(containing: selectedDate), id: \.self) { date in
                            NavigationLink {
                                ScheduledDayEditor(date: date)
                            } label: {
                                let plan = model.data.plan(for: date)
                                HStack(spacing: 12) {
                                    VStack {
                                        Text(DayKey.weekdayName(date)).font(.caption)
                                        Text(String(Calendar.current.component(.day, from: date))).bold()
                                            .foregroundStyle(Calendar.current.isDateInToday(date) ? Color.orange : Color.primary)
                                    }
                                    .frame(width: 32)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(plan.isRestDay ? "휴식" : plan.title)
                                        if !plan.isRestDay {
                                            Text(plan.exercises.map(\.name).joined(separator: ", "))
                                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.primary)
                            Divider()
                        }
                    }
                    Button {
                        confirmingRepeat = true
                    } label: {
                        Label("이 주 계획을 다음 주에도 반복", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Text("반복하면 이후 주의 같은 요일 계획을 덮어써요. 오늘과 지난 날짜는 바뀌지 않아요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("계획")
            .sheet(item: $calendarDay) { day in
                NavigationStack {
                    ScheduledDayEditor(date: day.date)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { calendarDay = nil } } }
                }
            }
            .confirmationDialog("이 주 계획을 몇 주 동안 반복할까요?", isPresented: $confirmingRepeat, titleVisibility: .visible) {
                ForEach([1, 2, 4, 8], id: \.self) { weeks in
                    Button("다음 \(weeks)주") { model.data.repeatWeek(containing: selectedDate, weeks: weeks) }
                }
            } message: {
                Text("이후 주의 계획을 이 주와 같게 덮어써요.")
            }
        }
    }
}

struct PlanningDay: Identifiable {
    let date: Date
    var id: String { DayKey.key(date) }
}

struct ScheduledDayEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    let date: Date
    @State private var session: PlanEditorSession?
    @State private var showingAdd = false
    @State private var showingCopy = false
    @State private var showingStarter = false
    @State private var showingName = false
    @State private var editing: Exercise?
    @State private var editMode = EditMode.inactive

    private var activeOnDate: Bool { model.data.activeWorkout?.day == DayKey.key(date) }

    var body: some View {
        Group {
            if let session { editor(session) }
            else { ProgressView() }
        }
        .onAppear { if session == nil { session = PlanEditorSession(model: model, date: date) } }
    }

    private func editor(_ session: PlanEditorSession) -> some View {
        Form {
            if !session.isCurrentOwner {
                Section { Text("계정이 바뀌었어요. 이 화면을 닫고 다시 열어 주세요.").foregroundStyle(.secondary) }
            }
            if activeOnDate || !model.data.workouts(on: date).isEmpty || Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: model.currentDate) {
                Section {
                    Text(activeOnDate
                         ? "이 날짜의 운동을 진행 중이에요. 운동을 마친 뒤 계획을 수정해 주세요."
                         : "지난 날짜도 계획을 수정할 수 있어요. 이미 저장한 운동 기록은 바뀌지 않아요.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !model.data.workouts(on: date).isEmpty {
                        NavigationLink("이 날짜 운동 기록 보기") { WorkoutJournalDayDetail(date: date) }
                    }
                }
            }
            if let failure = session.failure {
                Section { Label(failure, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
            }
            Section("계획 이름") {
                Button { showingName = true } label: {
                    HStack {
                        Text(session.plan.displayTitle)
                        Spacer()
                        Image(systemName: "pencil").foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary).disabled(activeOnDate || !session.isCurrentOwner)
                .accessibilityHint("계획 이름 변경")
            }
            if let deletion = session.deletion {
                Section {
                    Text("\(deletion.before.exercises.first(where: { !deletion.after.exercises.contains($0) })?.name ?? "운동")을 삭제했어요.")
                    Button("삭제 되돌리기") { session.undoDeletion() }.disabled(!session.canUndo)
                    if !session.canUndo { Text("계획이 바뀌어 이전 삭제를 되돌릴 수 없어요.").font(.footnote).foregroundStyle(.secondary) }
                }
            }
            Section {
                if session.plan.isRestDay { Text("아직 계획한 운동이 없어요. 아래에서 운동을 추가해 주세요.").foregroundStyle(.secondary) }
                ForEach(session.plan.exercises) { exercise in
                    Button { editing = exercise } label: {
                        HStack {
                            ExerciseSummary(exercise: exercise)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }.foregroundStyle(.primary)
                    .shortSwipeAction { session.remove(exercise) }
                }
                .onMove { session.move(from: $0, to: $1) }
            } header: { Text("계획한 운동") } footer: {
                Text("운동을 누르면 세트·횟수를 수정해요. 왼쪽으로 밀면 삭제하고, ‘순서 편집’에서 순서를 바꿀 수 있어요.")
            }
            .disabled(activeOnDate || !session.isCurrentOwner)
            Section {
                Button { showingAdd = true } label: { Label("운동 선택해서 추가", systemImage: "plus") }
                Button { showingStarter = true } label: { Label("기본 루틴 추가", systemImage: "list.bullet.clipboard") }
            } header: { Text("운동 추가") } footer: {
                Text("지금 계획한 운동을 유지하고 뒤에 추가해요.")
            }
            .disabled(activeOnDate || !session.isCurrentOwner)
            Section {
                Button("다른 계획으로 교체") { showingCopy = true }
            } header: { Text("계획 교체") } footer: {
                Text("다른 날짜나 요일의 계획으로 이 날짜의 운동 전체를 바꿔요. 교체 전에 내용을 확인할 수 있어요.")
            }
            .disabled(activeOnDate || !session.isCurrentOwner)
        }
        .environment(\.editMode, $editMode)
        .navigationTitle(date.formatted(.dateTime.month().day().weekday()))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(editMode.isEditing ? "완료" : "순서 편집") { editMode = editMode.isEditing ? .inactive : .active }
                    .disabled(activeOnDate || !session.isCurrentOwner || session.plan.isRestDay)
            }
        }
        .sheet(isPresented: $showingName) {
            PlanNameEditor(plan: session.plan, onSave: session.rename)
        }
        .sheet(isPresented: $showingStarter) { StarterWorkoutView(date: date, expectedOwner: session.ownerGeneration) }
        .sheet(isPresented: $showingAdd) { ExercisePicker(onSave: session.add) }
        .sheet(item: $editing) { exercise in
            ExerciseDraftView(exercise: exercise, title: "운동 수정") { saved in
                guard session.plan.exercises.contains(where: { $0.id == saved.id }) else { return false }
                return session.save { data in
                    var plan = data.plan(for: date)
                    if let i = plan.exercises.firstIndex(where: { $0.id == saved.id }) { plan.exercises[i] = saved }
                    data.scheduledPlans[DayKey.key(date)] = plan
                }
            }
        }
        .sheet(isPresented: $showingCopy) { PlanCopyView(targetDate: date, onCopy: session.replace) }
        .onChange(of: model.selection.generation) { _, _ in
            showingAdd = false
            showingCopy = false
            showingStarter = false
            showingName = false
            editing = nil
        }
    }
}

struct PlanNameEditor: View {
    @Environment(\.dismiss) private var dismiss
    let plan: DayPlan
    let onSave: (String) -> Bool
    @State private var draft: String
    @State private var failed = false

    init(plan: DayPlan, onSave: @escaping (String) -> Bool) {
        self.plan = plan
        self.onSave = onSave
        _draft = State(initialValue: plan.title == "휴식" ? "" : plan.title)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("예: 상체", text: $draft)
                        .accessibilityIdentifier("plan.name")
                } header: { Text("계획 이름") } footer: {
                    Text("비워 두면 운동 이름을 요약해서 보여 줘요.")
                }
                if failed { Text("저장하지 못했어요. 입력 내용은 남아 있으니 다시 시도해 주세요.").foregroundStyle(.red) }
            }
            .navigationTitle("계획 이름 변경")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { if onSave(draft) { dismiss() } else { failed = true } }
                }
            }
        }
        .protectEditingNavigation()
    }
}

struct PlanReplacement: Identifiable {
    let id = UUID()
    let source: DayPlan
    let sourceLabel: String
    let previous: DayPlan
}

struct PlanCopyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let targetDate: Date
    let onCopy: (DayPlan) -> Bool
    @State private var sourceDate: Date
    @State private var pending: PlanReplacement?

    init(targetDate: Date, onCopy: @escaping (DayPlan) -> Bool) {
        self.targetDate = targetDate
        self.onCopy = onCopy
        _sourceDate = State(initialValue: Calendar.current.date(byAdding: .day, value: -1, to: targetDate) ?? targetDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(targetDate, format: .dateTime.year().month().day().weekday())
                    Text("이 날짜의 운동 전체를 다른 계획으로 바꿔요. 원본 계획과 이미 저장한 운동 기록은 바뀌지 않아요.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("교체할 날짜") }
                Section("다른 날짜의 계획") {
                    DatePicker("가져올 날짜", selection: $sourceDate, displayedComponents: .date)
                    sourceRow(model.data.plan(for: sourceDate), label: sourceDate.formatted(.dateTime.month().day().weekday()),
                              sameDate: DayKey.key(sourceDate) == DayKey.key(targetDate))
                }
                Section("기존 요일 계획") {
                    ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { index in
                        sourceRow(model.data.week[index], label: "\(DayKey.weekdayNames[index])요일", sameDate: false)
                    }
                }
            }
            .navigationTitle("다른 계획으로 교체")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } }
            .sheet(item: $pending) { replacement in
                PlanReplacementReview(targetDate: targetDate, replacement: replacement) {
                    guard model.data.plan(for: targetDate) == replacement.previous else { return false }
                    guard onCopy(replacement.source) else { return false }
                    pending = nil
                    dismiss()
                    return true
                }
            }
        }
        .protectEditingNavigation()
    }

    private func sourceRow(_ source: DayPlan, label: String, sameDate: Bool) -> some View {
        Button {
            pending = PlanReplacement(source: source, sourceLabel: label, previous: model.data.plan(for: targetDate))
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(label) · \(source.displayTitle)")
                if sameDate { Text("현재 편집 중인 날짜예요.").font(.caption).foregroundStyle(.secondary) }
                else if source.isRestDay { Text("가져올 운동이 없는 휴식 계획이에요.").font(.caption).foregroundStyle(.secondary) }
                else { Text("운동 \(source.exercises.count)개 · \(source.exercises.map(\.name).joined(separator: ", "))").font(.caption).foregroundStyle(.secondary) }
            }
        }.disabled(sameDate || source.isRestDay)
    }
}

struct PlanReplacementReview: View {
    @Environment(\.dismiss) private var dismiss
    let targetDate: Date
    let replacement: PlanReplacement
    let onReplace: () -> Bool
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                Section("바꿀 날짜") { Text(targetDate, format: .dateTime.year().month().day().weekday()) }
                Section("현재 계획 · 운동 \(replacement.previous.exercises.count)개") {
                    Text(replacement.previous.displayTitle)
                    Text(replacement.previous.exercises.map(\.name).joined(separator: ", ")).foregroundStyle(.secondary)
                }
                Section("새 계획 · 운동 \(replacement.source.exercises.count)개") {
                    Text("\(replacement.sourceLabel) · \(replacement.source.displayTitle)")
                    ForEach(replacement.source.exercises) { ExerciseSummary(exercise: $0) }
                }
                Section {
                    Text("기존 운동 전체를 새 계획으로 바꿔요. 가져오는 원본 계획과 이미 저장한 운동 기록은 그대로 남아요.")
                    if failed { Text("교체하지 못했어요. 계획이나 계정이 바뀌었을 수 있어요. 취소 후 다시 선택하거나 재시도해 주세요.").foregroundStyle(.red) }
                }
            }
            .navigationTitle("계획을 교체할까요?")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("계획 교체") { if !onReplace() { failed = true } } }
            }
        }
        .interactiveDismissDisabled()
    }
}

struct ExerciseLibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    @State private var editing: Exercise?
    @State private var showingCatalog = false

    var body: some View {
        List {
            CatalogExerciseSection { editing = $0.makeExercise() }
            Section {
                ForEach(model.data.exerciseLibrary) { exercise in
                    Button { editing = exercise } label: { ExerciseSummary(exercise: exercise) }
                        .foregroundStyle(.primary)
                        .shortSwipeAction {
                            model.data.exerciseLibrary.removeAll { $0.id == exercise.id }
                        }
                }
                .onMove { model.data.exerciseLibrary.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text("내 운동 목록")
            } footer: {
                Text("위 운동 종목에서 선택해 기본 세트·횟수를 저장할 수 있어요.")
            }
        }
        .navigationTitle("운동 목록")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                EditButton()
            }
            ToolbarItem(placement: .primaryAction) {
                Button(account.canManageCatalog ? "운동 종목 관리" : "운동 종목 안내") { showingCatalog = true }
            }
        }
        .task { await account.refreshRecordCatalog() }
        .refreshable { await account.refreshRecordCatalog() }
        .sheet(isPresented: $showingCatalog) { RecordTypesView() }
        .sheet(item: $editing) { exercise in
            ExerciseDraftView(exercise: exercise, title: "운동 설정") { saved in
                model.saveEdit { data in
                    if let i = data.exerciseLibrary.firstIndex(where: { $0.id == saved.id }) {
                        data.exerciseLibrary[i] = saved
                    } else {
                        data.exerciseLibrary.append(saved)
                    }
                }
            }
        }
    }
}

struct ExercisePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    let onSave: (Exercise) -> Bool
    @State private var draft: Exercise?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if model.data.exerciseLibrary.isEmpty {
                        Text("아직 저장한 운동이 없어요. 운동 목록에서 기본 세트·횟수를 저장할 수 있어요.").foregroundStyle(.secondary)
                    }
                    ForEach(model.data.exerciseLibrary) { exercise in
                        let registered = model.data.isRegisteredExercise(exercise, catalog: account.catalogTypes)
                        Button {
                            var copy = exercise
                            copy.id = UUID()
                            draft = copy
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                ExerciseSummary(exercise: exercise)
                                if !registered { Text("현재 등록되지 않은 운동이에요.").font(.caption).foregroundStyle(.secondary) }
                            }
                        }.foregroundStyle(.primary).disabled(!registered)
                    }
                } header: { Text("내 운동 목록") } footer: {
                    Text("저장한 세트·횟수로 시작해요. 이 날짜에서 수정해도 원본 목록은 바뀌지 않아요.")
                }
                CatalogExerciseSection { draft = $0.makeExercise() }
            }
            .navigationTitle("운동 추가")
            .task { await account.refreshRecordCatalog() }
            .refreshable { await account.refreshRecordCatalog() }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } }
            .navigationDestination(item: $draft) { exercise in
                ExerciseDraftForm(exercise: exercise, title: "운동 설정", onCancel: { dismiss() }) { saved in
                    guard onSave(saved) else { return false }
                    dismiss()
                    return true
                }
            }
        }
        .protectEditingNavigation()
    }
}

/// Shared definitions stay outside the account's editable exercise library.
struct CatalogExerciseSection: View {
    @Environment(AccountModel.self) private var account
    let onSelect: (CatalogRecordType) -> Void

    var body: some View {
        Section {
            ForEach(CatalogRecordType.sorted(account.catalogTypes).filter(\.active)) { type in
                Button { onSelect(type) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(type.name)
                        if !type.hint.isEmpty {
                            Text(type.hint).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.foregroundStyle(.primary)
            }
            if !account.catalogTypes.contains(where: \.active) {
                Text("현재 사용할 수 있는 운동 종목이 없어요.").foregroundStyle(.secondary)
            }
            if let message = account.catalogMessage {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        } header: { Text("운동 종목") } footer: {
            Text("관리자가 등록한 운동이에요. 선택 후 내 세트·횟수·시간을 설정할 수 있어요.")
        }
    }
}

struct ExerciseSummary: View {
    let exercise: Exercise
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(exercise.name)
            Text("\(exercise.sets)세트 · \(exercise.detail)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ExerciseDraftView: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise
    let title: String
    let onSave: (Exercise) -> Bool
    var body: some View {
        NavigationStack {
            ExerciseDraftForm(exercise: exercise, title: title, onCancel: { dismiss() }) { saved in
                guard onSave(saved) else { return false }
                dismiss()
                return true
            }
        }
        .protectEditingNavigation()
    }
}

struct ExerciseDraftForm: View {
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    @State var exercise: Exercise
    let title: String
    let onCancel: () -> Void
    let onSave: (Exercise) -> Bool
    @State private var saveFailed = false
    @State private var owner: UUID?
    @State private var repetitions = RepetitionDraft()
    @State private var prepared = false

    private var invalidReps: Bool {
        guard prepared, exercise.plannedReps != nil, !isCindy else { return false }
        return !repetitions.isValid || (repetitions.usesDetails && repetitions.detailed.count != exercise.sets)
    }

    private var registered: Bool { model.data.isRegisteredExercise(exercise, catalog: account.catalogTypes) }
    private var isCindy: Bool { AppData.exerciseKey(exercise.name) == AppData.exerciseKey("신디") }

    var body: some View {
        Form {
            if saveFailed { Text("저장하지 못했어요. 입력 내용은 남아 있으니 다시 시도해 주세요.").foregroundStyle(.red) }
            if !registered { Text("현재 등록되지 않은 운동이에요. 운동 종목에서 다시 선택해 주세요.").foregroundStyle(.secondary) }
            if isCindy {
                Section {
                    Stepper(value: $exercise.sets, in: 1...20) {
                        LabeledContent("목표 세트 수") {
                            Text("\(exercise.sets)세트").monospacedDigit()
                        }
                    }
                }
                Section("1세트 구성") {
                    LabeledContent("풀업", value: "5회")
                    LabeledContent("푸쉬업", value: "10회")
                    LabeledContent("에어 스쿼트", value: "15회")
                }
            } else {
                LabeledContent("운동 종목", value: exercise.name)
                Stepper("\(exercise.sets)세트", value: Binding(
                    get: { exercise.sets },
                    set: { count in
                        exercise.resizeSetReps(to: count)
                        repetitions.resize(to: count)
                    }
                ), in: 1...20)
                .disabled(invalidReps)
                if exercise.plannedReps != nil {
                    Toggle("세트별 횟수 상세 설정", isOn: Binding(
                        get: { repetitions.usesDetails },
                        set: { enabled in
                            guard repetitions.setDetailed(enabled, count: exercise.sets) else { return }
                            if enabled {
                                exercise.applySetReps(repetitions.detailed.compactMap { RepetitionInput.value($0) })
                            } else { exercise.applySetReps(nil) }
                        }
                    )).disabled(invalidReps)
                    if repetitions.usesDetails {
                        ForEach(repetitions.detailed.indices, id: \.self) { index in
                            RepetitionInputRow(title: "\(index + 1)세트 목표", text: $repetitions.detailed[index])
                        }
                    } else {
                        RepetitionInputRow(title: "목표 횟수", text: $repetitions.common)
                    }
                } else {
                    TextField("시간·수행 조건", text: $exercise.detail)
                }
                if exercise.plannedReps != nil {
                    Text(exercise.setReps == nil
                         ? "모든 세트에 같은 횟수를 써요. 운동 중 −/+로 바꾼 횟수는 다음 세트에도 이어져요."
                         : "세트마다 정한 횟수로 시작해요. 운동 중 −/+로 그 세트만 바꿀 수 있어요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if exercise.hasPercentageTarget {
                    Text("비율 대신 횟수를 입력해 주세요. 예: 10회")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(isCindy ? "신디 설정" : title)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("취소", action: onCancel) }
            ToolbarItem(placement: .confirmationAction) {
                Button("저장") {
                    guard registered else { return }
                    exercise.name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard owner == model.selection.generation else { saveFailed = true; return }
                    guard !invalidReps else { return }
                    var saved = exercise
                    if !isCindy, exercise.plannedReps != nil {
                        guard let valid = repetitions.applying(to: exercise) else { return }
                        saved = valid
                    }
                    if !onSave(saved) { saveFailed = true }
                }.disabled(!registered || exercise.hasPercentageTarget || invalidReps)
            }
        }
        .onAppear {
            guard !prepared else { return }
            owner = model.selection.generation
            if exercise.hasPercentageTarget { exercise.detail = "10회" }
            if exercise.setReps != nil {
                exercise.resizeSetReps(to: min(max(exercise.sets, 1), 20))
            }
            repetitions = RepetitionDraft(exercise: exercise)
            prepared = true
        }
    }
}


struct RepetitionInputRow: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Stepper(value: Binding(get: { RepetitionInput.value(text) ?? 1 }, set: { text = String($0) }), in: 1...9999) {
                HStack {
                    Text(title)
                    Spacer()
                    TextField("1~9999", text: $text)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        .monospacedDigit().frame(minWidth: 64, minHeight: 44)
                        .accessibilityLabel(title + " 횟수 직접 입력")
                    Text("회")
                }
            }
            if RepetitionInput.value(text) == nil {
                Text("1~9999 사이의 정수로 입력해 주세요.").font(.footnote).foregroundStyle(.red)
            }
        }
    }
}
