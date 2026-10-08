import SwiftUI

struct RoutineView: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedDate: Date
    @State private var confirmingRepeat = false
    @State private var showAll = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            CalendarScrollView {
                CalendarSection("캘린더") {
                    Toggle("운동·일상 함께 보기", isOn: $showAll)
                    PlanCalendarView(selectedDate: $selectedDate, content: showAll ? .all : .workout)
                    Divider()
                    NavigationLink {
                        ScheduledDayEditor(date: selectedDate)
                    } label: {
                        HStack {
                            Label("선택한 날짜 계획 설정", systemImage: "calendar.badge.plus")
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                }
                CalendarSection("선택한 주의 운동") {
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
                    Button {
                        confirmingRepeat = true
                    } label: {
                        Label("이 주 계획을 다음 주에도 반복", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Text("반복하면 이후 주의 같은 요일 계획을 덮어써. 오늘과 지난 날짜는 바뀌지 않아.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                CalendarSection("운동 목록") {
                    NavigationLink {
                        ExerciseLibraryView()
                    } label: {
                        HStack {
                            Label("운동 목록", systemImage: "list.bullet.rectangle")
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                    Text("운동을 미리 만들어 두고 날짜별 계획에 가져올 수 있어. 일정은 자동으로 반복되지 않으니 '다음 주에도 반복'을 써 줘.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("계획")
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

struct ScheduledDayEditor: View {
    @Environment(AppModel.self) private var model
    let date: Date
    @State private var showingAdd = false
    @State private var showingCopy = false
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
                Text("운동을 모두 지우면 휴식일이 돼. 가져온 운동의 세트·횟수를 바꿔도 운동 목록은 그대로야.")
            }
            Section {
                Button("다른 날짜 / 기존 요일 계획 가져오기") { showingCopy = true }
            }
        }
        .navigationTitle(date.formatted(.dateTime.month().day().weekday()))
        .toolbar { EditButton() }
        .sheet(isPresented: $showingAdd) {
            ExercisePicker { exercise in
                var updated = plan.wrappedValue
                if updated.isRestDay && updated.title == "휴식" { updated.title = "운동" }
                updated.exercises.append(exercise)
                plan.wrappedValue = updated
            }
        }
        .sheet(item: $editing) { exercise in
            ExerciseDraftView(exercise: exercise, title: "운동 수정") { saved in
                var updated = plan.wrappedValue
                if let i = updated.exercises.firstIndex(where: { $0.id == saved.id }) {
                    updated.exercises[i] = saved
                    plan.wrappedValue = updated
                }
            }
        }
        .sheet(isPresented: $showingCopy) {
            PlanCopyView(targetDate: date) { source in
                var copy = source
                copy.exercises = source.exercises.map { exercise in
                    var next = exercise
                    next.id = UUID()
                    return next
                }
                plan.wrappedValue = copy
            }
        }
    }
}

struct PlanCopyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let targetDate: Date
    let onCopy: (DayPlan) -> Void
    @State private var sourceDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("날짜에서 가져오기") {
                    DatePicker("날짜", selection: $sourceDate, displayedComponents: .date)
                    let source = model.data.plan(for: sourceDate)
                    Button("\(source.title) 가져오기") { onCopy(source); dismiss() }
                        .disabled(DayKey.key(sourceDate) == DayKey.key(targetDate))
                }
                Section {
                    ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { i in
                        let source = model.data.week[i]
                        Button("\(DayKey.weekdayNames[i])요일 · \(source.title)") { onCopy(source); dismiss() }
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
    @State private var editing: Exercise?

    var body: some View {
        List {
            Section {
                ForEach(model.data.exerciseLibrary) { exercise in
                    Button { editing = exercise } label: { ExerciseSummary(exercise: exercise) }
                        .foregroundStyle(.primary)
                        .shortSwipeAction {
                            model.data.exerciseLibrary.removeAll { $0.id == exercise.id }
                        }
                }
                .onMove { model.data.exerciseLibrary.move(fromOffsets: $0, toOffset: $1) }
                Button {
                    editing = Exercise(name: "", sets: 3, detail: "10회")
                } label: {
                    Label("운동 만들기", systemImage: "plus")
                }
            } footer: {
                Text("기본 세트·횟수를 저장해 두면 계획에 바로 가져올 수 있어. 수정하거나 삭제해도 이미 배정한 운동은 유지돼.")
            }
        }
        .navigationTitle("운동 목록")
        .toolbar { EditButton() }
        .sheet(item: $editing) { exercise in
            ExerciseDraftView(exercise: exercise, title: "운동 설정") { saved in
                if let i = model.data.exerciseLibrary.firstIndex(where: { $0.id == saved.id }) {
                    model.data.exerciseLibrary[i] = saved
                } else {
                    model.data.exerciseLibrary.append(saved)
                }
            }
        }
    }
}

struct ExercisePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onSave: (Exercise) -> Void
    @State private var draft: Exercise?
    @State private var saveToLibrary = false

    var body: some View {
        NavigationStack {
            List {
                Section("운동 목록에서 가져오기") {
                    ForEach(model.data.exerciseLibrary) { exercise in
                        Button {
                            var copy = exercise
                            copy.id = UUID()
                            saveToLibrary = false
                            draft = copy
                        } label: { ExerciseSummary(exercise: exercise) }.foregroundStyle(.primary)
                    }
                    if model.data.exerciseLibrary.isEmpty {
                        Text("아래에서 첫 운동을 만들어 줘.").foregroundStyle(.secondary)
                    }
                }
                Button {
                    saveToLibrary = true
                    draft = Exercise(name: "", sets: 3, detail: "10회")
                } label: { Label("새 운동 만들기", systemImage: "plus") }
            }
            .navigationTitle("운동 추가")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } }
            .navigationDestination(item: $draft) { exercise in
                ExerciseDraftForm(exercise: exercise, title: "운동 설정", onCancel: { dismiss() }) { saved in
                    if saveToLibrary {
                        var template = saved
                        template.id = UUID()
                        model.data.exerciseLibrary.append(template)
                    }
                    onSave(saved)
                    dismiss()
                }
            }
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
    let onSave: (Exercise) -> Void
    var body: some View {
        NavigationStack {
            ExerciseDraftForm(exercise: exercise, title: title, onCancel: { dismiss() }) { saved in
                onSave(saved)
                dismiss()
            }
        }
    }
}

struct ExerciseDraftForm: View {
    @State var exercise: Exercise
    let title: String
    let onCancel: () -> Void
    let onSave: (Exercise) -> Void
    @FocusState private var nameFocused: Bool

    var body: some View {
        Form {
            TextField("운동 이름", text: $exercise.name).focused($nameFocused)
            Stepper("세트: \(exercise.sets)", value: $exercise.sets, in: 1...20)
            TextField("횟수·시간 (예: 10회, 1분)", text: $exercise.detail)
            if exercise.hasPercentageTarget {
                Text("비율 대신 횟수를 입력해 주세요. 예: 10회")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("취소", action: onCancel) }
            ToolbarItem(placement: .confirmationAction) {
                Button("저장") {
                    exercise.name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(exercise)
                }.disabled(exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                           || exercise.hasPercentageTarget)
            }
        }
        .onAppear {
            if exercise.hasPercentageTarget { exercise.detail = "10회" }
            nameFocused = exercise.name.isEmpty
        }
    }
}
