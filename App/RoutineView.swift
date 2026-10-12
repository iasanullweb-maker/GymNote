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
                    Text("반복하면 이후 주의 같은 요일 계획을 덮어써. 오늘과 지난 날짜는 바뀌지 않아.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("계획")
            .sheet(item: $calendarDay) { day in
                NavigationStack {
                    if model.data.workouts(on: day.date).isEmpty {
                        ScheduledDayEditor(date: day.date)
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { calendarDay = nil } } }
                    } else {
                        WorkoutJournalDayDetail(date: day.date)
                    }
                }
            }
            .confirmationDialog("이 주 계획을 몇 주 동안 반복할까?", isPresented: $confirmingRepeat, titleVisibility: .visible) {
                ForEach([1, 2, 4, 8], id: \.self) { weeks in
                    Button("다음 \(weeks)주") { model.data.repeatWeek(containing: selectedDate, weeks: weeks) }
                }
            } message: {
                Text("이후 주의 계획을 이 주와 같게 덮어써.")
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
    @State private var showingAdd = false
    @State private var showingCopy = false
    @State private var showingStarter = false
    @State private var editing: Exercise?

    private var plan: Binding<DayPlan> {
        Binding(get: { model.data.plan(for: date) }, set: { model.data.scheduledPlans[DayKey.key(date)] = $0 })
    }

    var body: some View {
        Form {
            Section("계획 이름") {
                TextField("예: 상체", text: plan.title)
            }
            Section {
                ForEach(plan.wrappedValue.exercises) { exercise in
                    Button { editing = exercise } label: {
                        ExerciseSummary(exercise: exercise)
                    }.foregroundStyle(.primary)
                    .shortSwipeAction {
                        var updated = plan.wrappedValue
                        updated.exercises.removeAll { $0.id == exercise.id }
                        plan.wrappedValue = updated
                    }
                }
                .onMove { source, destination in
                    var updated = plan.wrappedValue
                    updated.exercises.move(fromOffsets: source, toOffset: destination)
                    plan.wrappedValue = updated
                }
                Button { showingAdd = true } label: {
                    Label("운동 추가", systemImage: "plus")
                }
            } header: {
                Text("운동")
            } footer: {
                Text("운동 종목을 선택하고 이 날짜의 세트·횟수를 정하세요. 실행할 때 계획한 횟수로 시작해요.")
            }
            Section {
                Button("기본 루틴 선택해서 추가") { showingStarter = true }
                Button("다른 날짜 / 기존 요일 계획 가져오기") { showingCopy = true }
            }
        }
        .navigationTitle(date.formatted(.dateTime.month().day().weekday()))
        .toolbar { EditButton() }
        .sheet(isPresented: $showingStarter) { StarterWorkoutView(date: date) }
        .sheet(isPresented: $showingAdd) {
            ExercisePicker { exercise, saveToLibrary in
                model.saveEdit { data in
                    var updated = data.plan(for: date)
                    if updated.isRestDay && updated.title == "휴식" { updated.title = "운동" }
                    updated.exercises.append(exercise)
                    data.scheduledPlans[DayKey.key(date)] = updated
                    if saveToLibrary {
                        var template = exercise
                        template.id = UUID()
                        data.exerciseLibrary.append(template)
                    }
                }
            }
        }
        .sheet(item: $editing) { exercise in
            ExerciseDraftView(exercise: exercise, title: "운동 수정") { saved in
                guard model.data.plan(for: date).exercises.contains(where: { $0.id == saved.id }) else { return false }
                return model.saveEdit { data in
                    var updated = data.plan(for: date)
                    if let i = updated.exercises.firstIndex(where: { $0.id == saved.id }) { updated.exercises[i] = saved }
                    data.scheduledPlans[DayKey.key(date)] = updated
                }
            }
        }
        .sheet(isPresented: $showingCopy) {
            PlanCopyView(targetDate: date) { source in
                guard source.exercises.allSatisfy({ model.data.isRegisteredExercise($0, catalog: account.catalogTypes) }) else { return false }
                var copy = source
                copy.exercises = source.exercises.map { exercise in
                    var next = exercise
                    next.id = UUID()
                    return next
                }
                return model.saveEdit { $0.scheduledPlans[DayKey.key(date)] = copy }
            }
        }
    }
}

struct PlanCopyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let targetDate: Date
    let onCopy: (DayPlan) -> Bool
    @State private var sourceDate = Date()
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            Form {
                if saveFailed { Text("저장하지 못했어요. 다시 시도해 주세요.").foregroundStyle(.red) }
                Section("날짜에서 가져오기") {
                    DatePicker("날짜", selection: $sourceDate, displayedComponents: .date)
                    let source = model.data.plan(for: sourceDate)
                    Button("\(source.title) 가져오기") { if onCopy(source) { dismiss() } else { saveFailed = true } }
                        .disabled(DayKey.key(sourceDate) == DayKey.key(targetDate))
                }
                Section {
                    ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { i in
                        let source = model.data.week[i]
                        Button("\(DayKey.weekdayNames[i])요일 · \(source.title)") { if onCopy(source) { dismiss() } else { saveFailed = true } }
                    }
                } header: {
                    Text("기존 요일 계획")
                } footer: {
                    Text("가져오면 선택한 날짜의 계획을 교체해. 원본은 그대로 유지돼.")
                }
            }
            .navigationTitle("계획 가져오기")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } }
        }
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
    let onSave: (Exercise, Bool) -> Bool
    @State private var draft: Exercise?
    @State private var saveToLibrary = false

    var body: some View {
        NavigationStack {
            List {
                CatalogExerciseSection { type in
                    saveToLibrary = false
                    draft = type.makeExercise()
                }
            }
            .navigationTitle("운동 추가")
            .task { await account.refreshRecordCatalog() }
            .refreshable { await account.refreshRecordCatalog() }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } }
            .navigationDestination(item: $draft) { exercise in
                ExerciseDraftForm(exercise: exercise, title: "운동 설정", onCancel: { dismiss() }) { saved in
                    guard onSave(saved, saveToLibrary) else { return false }
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

    private var registered: Bool { model.data.isRegisteredExercise(exercise, catalog: account.catalogTypes) }

    var body: some View {
        Form {
            if saveFailed { Text("저장하지 못했어요. 입력 내용은 남아 있으니 다시 시도해 주세요.").foregroundStyle(.red) }
            if !registered { Text("현재 등록되지 않은 운동이에요. 운동 종목에서 다시 선택해 주세요.").foregroundStyle(.secondary) }
            LabeledContent("운동 종목", value: exercise.name)
            Stepper("세트: \(exercise.sets)", value: $exercise.sets, in: 1...20)
            if let reps = exercise.plannedReps {
                Stepper("목표 횟수: \(reps)회", value: Binding(
                    get: { exercise.plannedReps ?? reps },
                    set: { exercise.detail = "\($0)회" }
                ), in: 1...9999)
            } else {
                TextField("시간·수행 조건", text: $exercise.detail)
            }
            if exercise.hasPercentageTarget {
                Text("비율 대신 횟수를 입력해 주세요. 예: 10회")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(title)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("취소", action: onCancel) }
            ToolbarItem(placement: .confirmationAction) {
                Button("저장") {
                    guard registered else { return }
                    exercise.name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !onSave(exercise) { saveFailed = true }
                }.disabled(!registered || exercise.hasPercentageTarget)
            }
        }
        .onAppear {
            if exercise.hasPercentageTarget { exercise.detail = "10회" }
        }
    }
}
