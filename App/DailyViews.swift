import SwiftUI

struct DailyTodayView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: DailyItem?
    private var today: Date { Date() }
    private var scheduled: [DailyItem] { model.data.dailyItems(on: today) }
    private var undated: [DailyItem] {
        model.data.dailyItems.filter { $0.isUndated && !model.data.isDailyComplete($0, on: today) }
    }
    private var overdue: [DailyItem] {
        model.data.dailyItems.filter {
            !$0.isRepeating && ($0.scheduledDate.map { Calendar.current.startOfDay(for: $0) < Calendar.current.startOfDay(for: today) } ?? false)
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
                Section("오늘") {
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
                    } header: { Text("지난 미완료") }
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
                    NavigationLink("일상 관리") { DailyLibraryView() }
                }
            }
            .navigationTitle("일상")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = DailyItem(title: "", scheduledDate: today) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("일상 추가")
                }
            }
            .sheet(item: $editing) { DailyItemEditor(item: $0) }
        }
    }
}

/// '매일 · 🔔 21:00'처럼 반복과 알림을 한 줄로 보여 준다.
private struct DailyScheduleLine: View {
    let item: DailyItem
    var body: some View {
        HStack(spacing: 6) {
            Text(item.isRepeating ? item.scheduleDescription : (item.isUndated ? "날짜 미정" : "한 번 · " + item.scheduleDescription))
            if let time = item.reminderTime {
                Label(time.label, systemImage: "bell.fill").labelStyle(.titleAndIcon)
                    .accessibilityLabel("알림 \(time.label)")
            }
        }
        .font(.caption).foregroundStyle(.secondary)
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
                DailyScheduleLine(item: item)
                if !item.note.isEmpty { Text(item.note).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer()
            Button(action: edit) { Image(systemName: "pencil").frame(width: 36, height: 44) }
                .buttonStyle(.borderless).accessibilityLabel(item.title + " 편집")
        }
        .contextMenu {
            Button("편집", action: edit)
            if item.isRepeating && !completed {
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
                let skipped = model.data.dailyItems.filter { $0.isRepeating && $0.skippedDays.contains(DayKey.key(selectedDate)) }
                if !skipped.isEmpty {
                    Section("건너뛴 반복 일정") {
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
                NavigationLink("일상 관리") { DailyLibraryView() }
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
            // 반복 일정 먼저, 그다음 한 번 하는 일(날짜순, 미정은 마지막)
            let items = model.data.dailyItems.sorted {
                if $0.isRepeating != $1.isRepeating { return $0.isRepeating }
                return ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture)
            }
            ForEach(items) { item in
                Button { editing = item } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).foregroundStyle(.primary)
                        DailyScheduleLine(item: item)
                    }
                }
            }
            if model.data.dailyItems.isEmpty { Text("+ 버튼으로 일상을 만들어 보세요. 반복할지는 만들 때 정하면 돼요.").foregroundStyle(.secondary) }
        }
        .navigationTitle("일상 관리")
        .toolbar {
            Button { editing = DailyItem(title: "") } label: { Image(systemName: "plus") }
                .accessibilityLabel("일상 추가")
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
    @State private var remind: Bool
    @State private var reminderDate: Date
    @State private var confirmDelete = false

    init(item: DailyItem) {
        _draft = State(initialValue: item)
        _hasDate = State(initialValue: item.scheduledDate != nil)
        _date = State(initialValue: item.scheduledDate ?? Date())
        _remind = State(initialValue: item.reminderTime != nil)
        _reminderDate = State(initialValue: (item.reminderTime ?? ReminderTime(hour: 9, minute: 0)).pickerDate)
    }

    private var saved: Bool { model.data.dailyItems.contains { $0.id == draft.id } }
    /// 반복하지 않고 날짜도 없으면 알림을 울릴 날이 없다.
    private var canRemind: Bool { draft.isRepeating || hasDate }
    private var valid: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (draft.repeatChoice != .weekdays || !draft.weekdays.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("내용") {
                    TextField("이름 · 예: 독서, 과제 제출", text: $draft.title)
                    TextField("메모 (선택)", text: $draft.note, axis: .vertical).lineLimit(3...6)
                }
                Section {
                    Picker("반복", selection: $draft.repeatChoice) {
                        ForEach(DailyItem.RepeatChoice.allCases) { Text($0.title).tag($0) }
                    }
                    if draft.isRepeating {
                        DatePicker("시작 날짜", selection: $draft.startDate, displayedComponents: .date)
                        if draft.repeatChoice == .interval {
                            Stepper("\(draft.intervalDays)일마다", value: $draft.intervalDays, in: 1...365)
                        }
                        if draft.repeatChoice == .weekdays {
                            ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { day in
                                Toggle(DayKey.weekdayNames[day] + "요일", isOn: Binding(
                                    get: { draft.weekdays.contains(day) },
                                    set: { selected in
                                        draft.weekdays.removeAll { $0 == day }
                                        if selected { draft.weekdays.append(day) }
                                    }))
                            }
                        }
                    } else {
                        Toggle("날짜 지정", isOn: $hasDate)
                        if hasDate { DatePicker("날짜", selection: $date, displayedComponents: .date) }
                    }
                } header: { Text("일정") } footer: {
                    Text(draft.isRepeating
                         ? "반복 일정을 바꿔도 완료 기록은 그대로 남아요. 특정 날짜만 건너뛰려면 항목을 길게 눌러 주세요."
                         : "한 번 하는 일이에요. 완료하면 끝나고, 미완료 항목은 자동으로 다른 날짜로 옮기지 않아요.")
                }
                Section {
                    Toggle("알림", isOn: $remind).disabled(!canRemind)
                    if remind && canRemind {
                        DatePicker("시간", selection: $reminderDate, displayedComponents: .hourAndMinute)
                    }
                } header: { Text("알림") } footer: {
                    if !canRemind { Text("날짜를 정하면 알림을 받을 수 있어요.") }
                    else if !model.data.dailyReminders.enabled { Text("설정 탭에서 일상 알림이 꺼져 있어요. 켜야 울려요.") }
                    else { Text(draft.isRepeating ? "반복하는 날마다 이 시간에 울려요. 완료하거나 건너뛴 날에는 울리지 않아요."
                                : "지정한 날짜의 이 시간에 울려요. 먼저 완료하면 울리지 않아요.") }
                }
                if saved {
                    Section {
                        Button("항목 삭제", role: .destructive) { confirmDelete = true }
                    } footer: { Text("항목을 삭제해도 이미 저장된 완료 기록은 남아요. 예약된 알림은 함께 지워져요.") }
                }
            }
            .onChange(of: draft.repeatChoice) { old, new in
                // 날짜를 정해 둔 일을 반복으로 바꾸면 그 날짜부터 반복
                if old == .none, new != .none, hasDate { draft.startDate = date }
            }
            .navigationTitle(saved ? "일상 편집" : "일상 추가")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        draft.scheduledDate = !draft.isRepeating && hasDate ? date : nil
                        draft.reminderTime = remind && canRemind ? ReminderTime(reminderDate) : nil
                        let wantsReminder = draft.reminderTime != nil
                        model.data.saveDailyItemEditing(draft)
                        if wantsReminder { Task { await RestController.requestPermissions() } }
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
                    LabeledContent("완료한 일상", value: "\(completions.count)개")
                }
                Section {
                    let past = week.filter { Calendar.current.startOfDay(for: $0) <= Calendar.current.startOfDay(for: Date()) }
                    ForEach(model.data.dailyItems.filter(\.isRepeating)) { item in
                        let planned = past.filter { item.occurs(on: $0) }
                        let completed = planned.filter { model.data.isDailyComplete(item, on: $0) }.count
                        VStack(alignment: .leading, spacing: 6) {
                            LabeledContent(item.title, value: "\(completed) / \(planned.count)")
                            if !planned.isEmpty { ProgressView(value: Double(completed), total: Double(planned.count)).tint(.teal) }
                        }
                    }
                } header: { Text("반복 일정 달성률 · 이번 주 오늘까지") } footer: { Text("현재 반복 일정에서 예정된 날짜를 기준으로 계산해요. 건너뛴 날짜는 제외해요.") }
                Section("완료 기록") {
                    if days.isEmpty { Text("완료한 일상이 여기에 쌓여요.").foregroundStyle(.secondary) }
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
#Preview("일상 실행") {
    DailyPreview(plan: false)
}

#Preview("일상 계획") {
    DailyPreview(plan: true)
}

private struct DailyPreview: View {
    let plan: Bool
    @State private var selectedDate = Date()
    @State private var model: AppModel = {
        var data = AppData.sample
        data.saveDailyItem(DailyItem(title: "책상 정리", scheduledDate: Date()))
        data.saveDailyItem(DailyItem(title: "독서 20분", kind: .habit, reminderTime: ReminderTime(hour: 21, minute: 0)))
        data.saveDailyItem(DailyItem(title: "주말 약속 정하기"))
        return AppModel(previewData: data)
    }()

    var body: some View {
        Group {
            if plan { DailyPlansView(selectedDate: $selectedDate) }
            else { DailyTodayView() }
        }
        .environment(model)
    }
}