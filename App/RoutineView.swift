import SwiftUI

struct RoutineView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedDate = Date()

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section("캘린더") {
                    PlanCalendarView(selectedDate: $selectedDate)
                        .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 8))
                    NavigationLink {
                        ScheduledDayEditor(date: selectedDate)
                    } label: {
                        Label("선택한 날짜 계획 설정", systemImage: "calendar.badge.plus")
                    }
                }
                Section("선택한 주의 운동") {
                    ForEach(DayKey.weekDates(containing: selectedDate), id: \.self) { date in
                        NavigationLink {
                            ScheduledDayEditor(date: date)
                        } label: {
                            let plan = model.data.plan(for: date)
                            HStack(spacing: 12) {
                                VStack {
                                    Text(DayKey.weekdayName(date)).font(.caption)
                                    Text(date, format: .dateTime.day()).bold()
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
                                if Calendar.current.isDateInToday(date) {
                                    Text("오늘").font(.caption).foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
                Section {
                    NavigationLink {
                        ExerciseLibraryView()
                    } label: {
                        Label("운동 목록", systemImage: "list.bullet.rectangle")
                    }
                } footer: {
                    Text("운동을 미리 만들어 두고 날짜별 계획에 가져올 수 있어. 일정은 매주 반복되지 않아.")
                }
                Section("설정") {
                    Stepper("기본 휴식: \(model.data.defaultRest)초", value: $model.data.defaultRest, in: 15...600, step: 15)
                    Toggle("휴식 끝 알림 소리", isOn: $model.data.restSound)
                }
                Section("진단") {
                    LabeledContent("위젯 공유 저장소", value: SharedStore.diagnostics).font(.caption)
                }
            }
            .navigationTitle("계획")
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
                }
                .onDelete { offsets in
                    var updated = plan.wrappedValue
                    updated.exercises.remove(atOffsets: offsets)
                    plan.wrappedValue = updated
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
                }
                .onDelete { model.data.exerciseLibrary.remove(atOffsets: $0) }
                .onMove { model.data.exerciseLibrary.move(fromOffsets: $0, toOffset: $1) }
                Button {
                    editing = Exercise(name: "", sets: 3, detail: "10회", restSeconds: model.data.defaultRest)
                } label: {
                    Label("운동 만들기", systemImage: "plus")
                }
            } footer: {
                Text("기본 세트·횟수·휴식을 저장해 두면 계획에 바로 가져올 수 있어. 수정하거나 삭제해도 이미 배정한 운동은 유지돼.")
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
                    draft = Exercise(name: "", sets: 3, detail: "10회", restSeconds: model.data.defaultRest)
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
            Text("\(exercise.sets)세트 · \(exercise.detail) · 휴식 \(exercise.restSeconds)초")
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
            Stepper("세트 사이 휴식: \(exercise.restSeconds)초", value: $exercise.restSeconds, in: 0...600, step: 15)
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("취소", action: onCancel) }
            ToolbarItem(placement: .confirmationAction) {
                Button("저장") {
                    exercise.name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(exercise)
                }.disabled(exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear { nameFocused = exercise.name.isEmpty }
    }
}
