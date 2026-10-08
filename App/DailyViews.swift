import SwiftUI

struct DailyTodayView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: DailyItem?
    private var today: Date { Date() }
    private var scheduled: [DailyItem] { model.data.dailyItems(on: today) }
    private var undated: [DailyItem] {
        model.data.dailyItems.filter { $0.kind == .task && $0.scheduledDate == nil && !model.data.isDailyComplete($0, on: today) }
    }
    private var overdue: [DailyItem] {
        model.data.dailyItems.filter {
            $0.kind == .task && ($0.scheduledDate.map { Calendar.current.startOfDay(for: $0) < Calendar.current.startOfDay(for: today) } ?? false)
                && !model.data.isDailyComplete($0, on: today)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    let done = scheduled.filter { model.data.isDailyComplete($0, on: today) }.count
                    LabeledContent("오늘의 일상", value: "\(done) / \(scheduled.count) 완료")
                    if !scheduled.isEmpty { ProgressView(value: Double(done), total: Double(scheduled.count)).tint(.teal) }
                    Text(today, format: .dateTime.year().month().day().weekday())
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("오늘 할 일·습관") {
                    if scheduled.isEmpty { Text("오늘 예정된 항목이 없어요. + 버튼으로 추가해 보세요.").foregroundStyle(.secondary) }
                    ForEach(scheduled) { item in
                        DailyItemRow(item: item, date: today) { editing = item }
                    }
                }
                if !overdue.isEmpty {
                    Section {
                        ForEach(overdue) { item in
                            // 지난 일정은 원래 날짜로 기록. 다른 날짜로 옮기기는 편집에서 선택.
                            DailyItemRow(item: item, date: item.scheduledDate ?? today) { editing = item }
                        }
                    } header: { Text("지난 미완료 할 일") }
                      footer: { Text("날짜는 자동으로 옮기지 않아요. 편집에서 날짜를 바꾸거나 원래 날짜에 완료 표시할 수 있어요.") }
                }
                if !undated.isEmpty {
                    Section("날짜 미정") {
                        ForEach(undated) { item in
                            DailyItemRow(item: item, date: today) { editing = item }
                        }
                    }
                }
                Section {
                    NavigationLink("할 일·습관 관리") { DailyLibraryView() }
                }
            }
            .navigationTitle("일상")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = DailyItem(title: "", scheduledDate: today) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("할 일 또는 습관 추가")
                }
            }
            .sheet(item: $editing) { DailyItemEditor(item: $0) }
        }
    }
}

private struct DailyItemRow: View {
    @Environment(AppModel.self) private var model
    let item: DailyItem
    let date: Date
    let edit: () -> Void

    var body: some View {
        let completed = model.data.isDailyComplete(item, on: date)
        HStack(spacing: 12) {
            Button { model.data.toggleDailyCompletion(item.id, on: date) } label: {
                Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(completed ? Color.teal : Color.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(item.title + (completed ? " 완료 취소" : " 완료"))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).strikethrough(completed).foregroundStyle(completed ? .secondary : .primary)
                Text(item.kind.title + " · " + item.scheduleDescription)
                    .font(.caption).foregroundStyle(.secondary)
                if !item.note.isEmpty { Text(item.note).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer()
            Button(action: edit) { Image(systemName: "pencil").frame(width: 36, height: 44) }
                .buttonStyle(.borderless).accessibilityLabel(item.title + " 편집")
        }
        .contextMenu {
            Button("편집", action: edit)
            if item.kind == .habit && !completed {
                Button("이 날짜 건너뛰기") { model.data.skipDailyHabit(item.id, on: date) }
            }
        }
    }
}

struct DailyPlansView: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedDate: Date
    @State private var editing: DailyItem?
    @State private var showAll = false

    var body: some View {
        NavigationStack {
            List {
                Section("캘린더") {
                    Toggle("운동·일상 함께 보기", isOn: $showAll)
                    PlanCalendarView(selectedDate: $selectedDate, content: showAll ? .all : .daily)
                        .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 8))
                    if showAll {
                        Text("운동은 기본 글씨, 일상은 청록색으로 표시해요.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    let items = model.data.dailyItems(on: selectedDate)
                    if items.isEmpty { Text("예정된 항목이 없어요.").foregroundStyle(.secondary) }
                    ForEach(items) { item in
                        DailyItemRow(item: item, date: selectedDate) { editing = item }
                    }
                    Button {
                        editing = DailyItem(title: "", scheduledDate: selectedDate, startDate: selectedDate)
                    } label: { Label("이 날짜에 추가", systemImage: "plus") }
                } header: { Text(selectedDate.formatted(.dateTime.year().month().day().weekday())) }
                let skipped = model.data.dailyItems.filter { $0.kind == .habit && $0.skippedDays.contains(DayKey.key(selectedDate)) }
                if !skipped.isEmpty {
                    Section("건너뛴 습관") {
                        ForEach(skipped) { item in
                            Button("\(item.title) · 다시 예정하기") {
                                guard let index = model.data.dailyItems.firstIndex(where: { $0.id == item.id }) else { return }
                                model.data.dailyItems[index].skippedDays.remove(DayKey.key(selectedDate))
                            }
                        }
                    }
                }
                Section("선택한 주") {
                    ForEach(DayKey.weekDates(containing: selectedDate), id: \.self) { date in
                        Button { selectedDate = date } label: {
                            HStack {
                                Text("\(DayKey.weekdayName(date)) \(Calendar.current.component(.day, from: date))").frame(width: 44)
                                Text(model.data.dailyItems(on: date).map(\.title).joined(separator: ", "))
                                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                if Calendar.current.isDate(date, inSameDayAs: selectedDate) { Image(systemName: "checkmark") }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
                NavigationLink("할 일·습관 관리") { DailyLibraryView() }
            }
            .navigationTitle("일상 계획")
            .sheet(item: $editing) { DailyItemEditor(item: $0) }
        }
    }
}

private struct DailyLibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: DailyItem?

    var body: some View {
        List {
            ForEach(DailyItem.Kind.allCases, id: \.self) { kind in
                Section(kind.title) {
                    ForEach(model.data.dailyItems.filter { $0.kind == kind }) { item in
                        Button { editing = item } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).foregroundStyle(.primary)
                                Text(item.scheduleDescription).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if model.data.dailyItems.isEmpty { Text("할 일이나 습관을 만들어 보세요.").foregroundStyle(.secondary) }
        }
        .navigationTitle("할 일·습관 관리")
        .toolbar {
            Button { editing = DailyItem(title: "") } label: { Image(systemName: "plus") }
                .accessibilityLabel("할 일 또는 습관 추가")
        }
        .sheet(item: $editing) { DailyItemEditor(item: $0) }
    }
}

private struct DailyItemEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DailyItem
    @State private var hasDate: Bool
    @State private var date: Date
    @State private var confirmDelete = false

    init(item: DailyItem) {
        _draft = State(initialValue: item)
        _hasDate = State(initialValue: item.scheduledDate != nil)
        _date = State(initialValue: item.scheduledDate ?? Date())
    }

    private var saved: Bool { model.data.dailyItems.contains { $0.id == draft.id } }
    private var valid: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (draft.kind != .habit || draft.repeatRule != .weekdays || !draft.weekdays.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("내용") {
                    TextField("이름 · 예: 독서, 과제 제출", text: $draft.title)
                    if !saved {
                        Picker("종류", selection: $draft.kind) {
                            ForEach(DailyItem.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented)
                    } else { LabeledContent("종류", value: draft.kind.title) }
                    TextField("메모 (선택)", text: $draft.note, axis: .vertical).lineLimit(3...6)
                }
                if draft.kind == .task {
                    Section("일정") {
                        Toggle("날짜 지정", isOn: $hasDate)
                        if hasDate { DatePicker("날짜", selection: $date, displayedComponents: .date) }
                        Text("날짜를 바꾸면 해당 날짜로 이동해요. 미완료 항목은 자동으로 이동하지 않아요.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        DatePicker("시작 날짜", selection: $draft.startDate, displayedComponents: .date)
                        Picker("반복", selection: $draft.repeatRule) {
                            ForEach(DailyItem.RepeatRule.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        if draft.repeatRule == .interval { Stepper("\(draft.intervalDays)일마다", value: $draft.intervalDays, in: 1...365) }
                        if draft.repeatRule == .weekdays {
                            ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { day in
                                Toggle(DayKey.weekdayNames[day] + "요일", isOn: Binding(
                                    get: { draft.weekdays.contains(day) },
                                    set: { selected in
                                        draft.weekdays.removeAll { $0 == day }
                                        if selected { draft.weekdays.append(day) }
                                    }))
                            }
                        }
                    } header: { Text("반복 일정") } footer: { Text("반복 일정을 바꿔도 완료 기록은 그대로 남아요. 특정 날짜만 건너뛰려면 항목을 길게 눌러 주세요.") }
                }
                if saved {
                    Section {
                        Button("항목 삭제", role: .destructive) { confirmDelete = true }
                    } footer: { Text("항목을 삭제해도 이미 저장된 완료 기록은 남아요.") }
                }
            }
            .navigationTitle(saved ? "일상 편집" : "일상 추가")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        draft.scheduledDate = draft.kind == .task && hasDate ? date : nil
                        model.data.saveDailyItem(draft)
                        dismiss()
                    }.disabled(!valid)
                }
            }
            .confirmationDialog("이 항목을 삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("삭제", role: .destructive) {
                    model.data.dailyItems.removeAll { $0.id == draft.id }
                    dismiss()
                }
            }
        }
    }
}

struct DailyHistoryView: View {
    @Environment(AppModel.self) private var model
    private var days: [String] { Array(Set(model.data.dailyCompletions.map(\.day))).sorted(by: >) }
    private var week: [Date] { DayKey.weekDates(containing: Date()) }

    var body: some View {
        NavigationStack {
            List {
                Section("이번 주") {
                    let keys = Set(week.map { DayKey.key($0) })
                    let completions = model.data.dailyCompletions.filter { keys.contains($0.day) }
                    LabeledContent("완료한 할 일", value: "\(completions.filter { $0.kind == .task }.count)개")
                    LabeledContent("습관 실천", value: "\(completions.filter { $0.kind == .habit }.count)회")
                }
                Section {
                    let past = week.filter { Calendar.current.startOfDay(for: $0) <= Calendar.current.startOfDay(for: Date()) }
                    ForEach(model.data.dailyItems.filter { $0.kind == .habit }) { item in
                        let planned = past.filter { item.occurs(on: $0) }
                        let completed = planned.filter { model.data.isDailyComplete(item, on: $0) }.count
                        VStack(alignment: .leading, spacing: 6) {
                            LabeledContent(item.title, value: "\(completed) / \(planned.count)")
                            if !planned.isEmpty { ProgressView(value: Double(completed), total: Double(planned.count)).tint(.teal) }
                        }
                    }
                } header: { Text("습관 달성률 · 이번 주 오늘까지") } footer: { Text("현재 반복 일정에서 예정된 날짜를 기준으로 계산해요. 건너뛴 날짜는 제외해요.") }
                Section("완료 기록") {
                    if days.isEmpty { Text("완료한 할 일과 습관이 여기에 쌓여요.").foregroundStyle(.secondary) }
                    ForEach(days, id: \.self) { day in
                        NavigationLink {
                            DailyHistoryDayView(day: day)
                        } label: {
                            LabeledContent(day, value: "\(model.data.dailyCompletions.filter { $0.day == day }.count)개 완료")
                        }
                    }
                }
            }
            .navigationTitle("일상 기록")
        }
    }
}

private struct DailyHistoryDayView: View {
    @Environment(AppModel.self) private var model
    let day: String
    @State private var removing: DailyCompletion?

    var body: some View {
        List {
            ForEach(model.data.dailyCompletions.filter { $0.day == day }.sorted { $0.completedAt > $1.completedAt }) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    Label(entry.title, systemImage: entry.kind == .habit ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                    Text(entry.kind.title + " · 완료 " + entry.completedAt.formatted(.dateTime.month().day().hour().minute()))
                        .font(.caption).foregroundStyle(.secondary)
                    if !entry.note.isEmpty { Text(entry.note).font(.subheadline).foregroundStyle(.secondary) }
                }
                .swipeActions {
                    Button("완료 취소", role: .destructive) { removing = entry }
                }
            }
        }
        .navigationTitle(day)
        .confirmationDialog("완료 기록을 취소할까요?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("완료 취소", role: .destructive) {
                if let entry = removing { model.data.dailyCompletions.removeAll { $0.id == entry.id } }
                removing = nil
            }
        }
    }
}