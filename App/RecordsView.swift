import Charts
import SwiftUI

struct RecordsView: View {
    @Environment(AppModel.self) private var model
    @State private var addingFor: RecordType?
    @State private var showingTypes = false
    @State private var prMessage: String?
    @State private var showingJournal = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("기록 종류", selection: $showingJournal) {
                    Text("최고 기록").tag(false)
                    Text("운동 일지").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                if showingJournal {
                    WorkoutJournalView()
                } else {
                    List {
                        if model.data.recordTypes.isEmpty {
                            Text("종목이 없어. 아래 '종목 추가 · 편집'에서 추가해 줘.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(model.data.recordTypes) { type in
                            RecordSection(type: type) { addingFor = type }
                        }

                        Section {
                            Button {
                                showingTypes = true
                            } label: {
                                Label("종목 추가 · 편집 · 순서", systemImage: "slider.horizontal.3")
                            }
                        } footer: {
                            Text("위에 있는 3개 종목이 위젯에 표시돼.")
                        }
                    }
                }
            }
            .navigationTitle("기록")
            .sheet(item: $addingFor) { type in
                AddRecordView(types: model.data.recordTypes, fixedTypeID: type.id) { entry in
                    if model.addRecord(entry), let type = model.data.recordType(entry.typeID) {
                        prMessage = "\(type.name) \(type.display(entry))"
                    }
                }
            }
            .sheet(isPresented: $showingTypes) {
                RecordTypesView().environment(model)
            }
            .alert("🎉 신기록!", isPresented: Binding(
                get: { prMessage != nil },
                set: { if !$0 { prMessage = nil } }
            )) {
                Button("확인") { prMessage = nil }
            } message: {
                Text(prMessage ?? "")
            }
        }
    }
}

struct RecordSection: View {
    @Environment(AppModel.self) private var model
    let type: RecordType
    let onAdd: () -> Void

    var body: some View {
        let entries = model.data.entries(type)
        let best = model.data.best(type)

        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("최고 기록")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(best.map { type.display($0) } ?? "아직 없음")
                        .font(.title2)
                        .bold()
                }
                Spacer()
                if let best = best {
                    Text(best.date, format: .dateTime.year().month().day())
                        .foregroundStyle(.secondary)
                }
            }

            if !entries.isEmpty {
                Chart(entries) { entry in
                    if entries.count >= 2 {
                        LineMark(
                            x: .value("날짜", entry.date),
                            y: .value(type.style == .rounds ? "총 반복" : "기록", type.score(entry))
                        )
                    }
                    PointMark(
                        x: .value("날짜", entry.date),
                        y: .value(type.style == .rounds ? "총 반복" : "기록", type.score(entry))
                    )
                }
                .foregroundStyle(.orange)
                .frame(height: 140)
                .accessibilityLabel("\(type.name) 기록 추이")
                if entries.count == 1 {
                    Text("첫 기록이에요. 다음 기록부터 변화가 선으로 이어져요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.title2)
                    Text("기록을 추가하면 변화가 그래프로 보여요")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 140)
            }

            NavigationLink {
                RecordHistoryView(typeID: type.id)
            } label: {
                Text("전체 기록 보기 (\(entries.count)개)")
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text(type.name)
                Spacer()
                Button(action: onAdd) {
                    Label("기록", systemImage: "plus.circle.fill")
                        .font(.subheadline.bold())
                }
                .buttonStyle(.borderless)
                .tint(.orange)
                .accessibilityLabel("\(type.name) 기록 추가")
            }
            .textCase(nil)
        }
    }
}

/// 기록 한 줄: 탭하면 수정, 왼쪽으로 밀면 삭제
struct RecordRow: View {
    @Environment(AppModel.self) private var model
    let type: RecordType
    let entry: RecordEntry
    var isBest: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(entry.date, format: .dateTime.year().month().day())
                    .foregroundStyle(.primary)
                Spacer()
                if isBest {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(.orange)
                }
                Text(type.display(entry))
                    .foregroundStyle(.primary)
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .swipeActions {
            Button("삭제", role: .destructive) {
                model.data.records.removeAll { $0.id == entry.id }
            }
        }
    }
}

// MARK: - 전체 기록

struct RecordHistoryView: View {
    @Environment(AppModel.self) private var model
    let typeID: String
    @State private var editing: RecordEntry?

    var body: some View {
        let type = model.data.recordType(typeID)
        let entries: [RecordEntry] = type.map { Array(model.data.entries($0).reversed()) } ?? []
        let best = type.flatMap { model.data.best($0) }

        List {
            if let type = type {
                Section {
                    ForEach(entries) { entry in
                        RecordRow(type: type, entry: entry, isBest: entry.id == best?.id) { editing = entry }
                    }
                } footer: {
                    Text("탭하면 수정, 왼쪽으로 밀면 삭제")
                }
            }
        }
        .navigationTitle(type?.name ?? "기록")
        .overlay {
            if entries.isEmpty {
                Text("기록이 없어").foregroundStyle(.secondary)
            }
        }
        .sheet(item: $editing) { entry in
            AddRecordView(types: model.data.recordTypes, existing: entry) { updated in
                model.data.updateRecord(updated)
            }
        }
    }
}

// MARK: - 기록 추가 / 수정

struct AddRecordView: View {
    @Environment(\.dismiss) private var dismiss
    let types: [RecordType]
    let existing: RecordEntry?
    let lockType: Bool
    let onSave: (RecordEntry) -> Void

    @State private var typeID: String
    @State private var value: Double?
    @State private var extra: Int?
    @State private var date: Date

    /// fixedTypeID를 주면 그 종목으로 고정 (종목 선택 칸 숨김)
    init(types: [RecordType], existing: RecordEntry? = nil, fixedTypeID: String? = nil,
         onSave: @escaping (RecordEntry) -> Void) {
        self.types = types
        self.existing = existing
        self.lockType = fixedTypeID != nil
        self.onSave = onSave
        _typeID = State(initialValue: fixedTypeID ?? existing?.typeID ?? types.first?.id ?? "")
        _value = State(initialValue: existing?.value)
        _extra = State(initialValue: existing.map { $0.extraReps })
        _date = State(initialValue: existing?.date ?? Date())
    }

    private var type: RecordType? { types.first { $0.id == typeID } ?? types.first }

    var body: some View {
        NavigationStack {
            Form {
                if !lockType {
                    Picker("종목", selection: $typeID) {
                        ForEach(types) { t in
                            Text(t.name).tag(t.id)
                        }
                    }
                }

                if let type = type {
                    Section {
                        if type.style == .rounds {
                            TextField("라운드", value: $value, format: .number)
                                .keyboardType(.numberPad)
                            TextField("추가 횟수", value: $extra, format: .number)
                                .keyboardType(.numberPad)
                        } else {
                            HStack {
                                TextField("기록", value: $value, format: .number)
                                    .keyboardType(.decimalPad)
                                Text(type.unit)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        DatePicker("날짜", selection: $date, displayedComponents: .date)
                    } footer: {
                        if !type.hint.isEmpty { Text(type.hint) }
                    }
                }
            }
            .navigationTitle(existing != nil ? "기록 수정" : (lockType ? "\(type?.name ?? "") 기록" : "기록 추가"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .disabled((value ?? -1) < 0)
                }
            }
            .onChange(of: typeID) { _, _ in
                value = nil
                extra = nil
            }
        }
    }

    private func save() {
        guard let type = type, let v = value, v >= 0 else { return }
        var entry = RecordEntry(typeID: type.id, date: date, value: v)
        if let existing = existing { entry.id = existing.id }
        if type.style == .rounds {
            // 추가 횟수가 라운드당 횟수를 넘으면 라운드로 넘김
            let perRound = max(type.repsPerRound, 1)
            let total = Int(v) * perRound + max(extra ?? 0, 0)
            entry.value = Double(total / perRound)
            entry.extraReps = total % perRound
        }
        onSave(entry)
        dismiss()
    }
}

// MARK: - 종목 편집

struct RecordTypesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var adding: RecordType?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(model.data.recordTypes.enumerated()), id: \.element.id) { index, type in
                        NavigationLink {
                            RecordTypeEditor(typeID: type.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(type.name)
                                    Text(summary(type))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if index < 3 {
                                    Text("위젯")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.2), in: Capsule())
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                    .onMove { source, destination in
                        model.data.recordTypes.move(fromOffsets: source, toOffset: destination)
                    }

                    Button {
                        adding = RecordType(name: "")
                    } label: {
                        Label("종목 추가", systemImage: "plus")
                    }
                } footer: {
                    Text("위에 있는 3개가 위젯에 표시돼. 오른쪽 위 '편집'을 눌러 순서를 바꿀 수 있어.")
                }
            }
            .navigationTitle("기록 종목")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .sheet(item: $adding) { type in
                NewRecordTypeView(type: type) { model.data.recordTypes.append($0) }
            }
        }
    }

    private func summary(_ type: RecordType) -> String {
        if type.style == .rounds { return "라운드 + 추가 횟수 · 라운드당 \(type.repsPerRound)회" }
        var text = type.unit.isEmpty ? "숫자" : "단위: \(type.unit)"
        if type.lowerIsBetter { text += " · 낮을수록 좋음" }
        return text
    }
}

struct NewRecordTypeView: View {
    @Environment(\.dismiss) private var dismiss
    @State var type: RecordType
    let onSave: (RecordType) -> Void
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("종목 이름", text: $type.name).focused($nameFocused)
                Picker("기록 방식", selection: $type.style) {
                    Text("숫자").tag(RecordType.Style.count)
                    Text("라운드 + 횟수").tag(RecordType.Style.rounds)
                }.pickerStyle(.segmented)
                if type.style == .count {
                    TextField("단위 (예: 회, kg, 초)", text: $type.unit)
                    Toggle("낮을수록 좋은 기록", isOn: $type.lowerIsBetter)
                } else {
                    Stepper("라운드당 횟수: \(type.repsPerRound)", value: $type.repsPerRound, in: 1...500)
                }
                TextField("설명", text: $type.hint, axis: .vertical)
            }
            .navigationTitle("종목 추가")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        type.name = type.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(type)
                        dismiss()
                    }.disabled(type.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { nameFocused = true }
        }
    }
}

struct RecordTypeEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let typeID: String
    @State private var confirmingDelete = false

    /// ID로 찾아서 편집 (삭제해도 앱이 멈추지 않게)
    private var type: Binding<RecordType> {
        Binding(
            get: { model.data.recordType(typeID) ?? RecordType(id: typeID, name: "") },
            set: { newValue in
                if let i = model.data.recordTypes.firstIndex(where: { $0.id == typeID }) {
                    model.data.recordTypes[i] = newValue
                }
            }
        )
    }

    var body: some View {
        let count = model.data.records.filter { $0.typeID == typeID }.count

        Form {
            Section("이름") {
                TextField("예: 스쿼트 1RM", text: type.name)
            }

            Section {
                Picker("기록 방식", selection: type.style) {
                    Text("숫자").tag(RecordType.Style.count)
                    Text("라운드 + 횟수").tag(RecordType.Style.rounds)
                }
                .pickerStyle(.segmented)

                if type.wrappedValue.style == .count {
                    TextField("단위 (예: 회, kg, 초)", text: type.unit)
                    Toggle("낮을수록 좋은 기록", isOn: type.lowerIsBetter)
                } else {
                    Stepper("라운드당 횟수: \(type.wrappedValue.repsPerRound)", value: type.repsPerRound, in: 1...500)
                }
            } footer: {
                Text(type.wrappedValue.style == .count
                     ? "달리기 시간처럼 짧을수록 좋은 기록이면 '낮을수록 좋은 기록'을 켜."
                     : "신디 같은 AMRAP용. 라운드당 횟수로 총 반복 수를 계산해서 비교해.")
            }

            Section("설명 (기록 추가할 때 보임)") {
                TextField("예: 한 세트 최대 반복 횟수", text: type.hint, axis: .vertical)
            }

            Section {
                Button("종목 삭제", role: .destructive) { confirmingDelete = true }
            }
        }
        .navigationTitle(type.wrappedValue.name.isEmpty ? "종목" : type.wrappedValue.name)
        .confirmationDialog(
            "'\(type.wrappedValue.name)' 종목을 삭제할까?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("삭제 (기록 \(count)개도 함께 삭제)", role: .destructive) {
                let id = typeID
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    model.data.deleteRecordType(id)
                }
            }
        }
    }
}
