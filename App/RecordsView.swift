import Charts
import SwiftUI

struct RecordsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
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
                        if let message = account.catalogMessage {
                            Text(message).font(.footnote).foregroundStyle(.secondary)
                        }
                        if account.catalogTypes.filter(\.active).isEmpty {
                            Text("현재 사용할 수 있는 공통 종목이 없어요.").foregroundStyle(.secondary)
                        }
                        ForEach(account.catalogTypes.filter(\.active)) { definition in
                            RecordSection(type: definition.recordType) { addingFor = definition.recordType }
                        }
                        ForEach(account.catalogTypes.filter { !$0.active && !model.data.entries($0.recordType).isEmpty }) { definition in
                            RecordSection(type: definition.recordType, allowsAdding: false) {}
                        }
                        if !legacyTypes.isEmpty {
                            Section {
                                ForEach(legacyTypes) { type in
                                    NavigationLink(type.name) { RecordHistoryView(typeID: type.id) }
                                }
                            } header: { Text("이전 개인 기록") } footer: {
                                Text("기존 기록은 보존됩니다. 새 기록은 공통 종목에 입력해 주세요.")
                            }
                        }
                        Section {
                            Button { showingTypes = true } label: {
                                Label(account.canManageCatalog ? "공통 종목 관리" : "공통 종목 안내", systemImage: "list.bullet")
                            }
                        } footer: {
                            Text("사용 중인 공통 종목의 앞 3개가 위젯에 표시돼요.")
                        }
                    }
                }
            }
            .navigationTitle("기록")
            .task(id: account.user?.id) { await account.refreshRecordCatalog() }
            .onChange(of: account.user?.id) { _, _ in
                addingFor = nil
                showingTypes = false
            }
            .refreshable { await account.refreshRecordCatalog() }
            .sheet(item: $addingFor) { type in
                AddRecordView(types: account.catalogTypes.filter(\.active).map(\.recordType), fixedTypeID: type.id) { entry in
                    if model.addRecord(entry), let type = account.catalogTypes.first(where: { $0.id == entry.typeID })?.recordType {
                        prMessage = "\(type.name) \(type.display(entry))"
                    }
                }
            }
            .sheet(isPresented: $showingTypes) {
                RecordTypesView()
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
    private var legacyTypes: [RecordType] {
        let commonIDs = Set(account.catalogTypes.map(\.id))
        return model.data.recordTypes.filter { !commonIDs.contains($0.id) && !model.data.entries($0).isEmpty }
    }

}

struct RecordSection: View {
    @Environment(AppModel.self) private var model
    let type: RecordType
    var allowsAdding = true
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
                    .font(.title3.bold())
                Spacer()
                if allowsAdding {
                    Button(action: onAdd) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderless)
                    .tint(.orange)
                    .accessibilityLabel("\(type.name) 기록 추가")
                }
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
    @Environment(AccountModel.self) private var account
    let typeID: String
    @State private var editing: RecordEntry?

    var body: some View {
        let type = model.data.recordDisplayTypes(catalog: account.catalogTypes).first { $0.id == typeID }
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
        .onChange(of: account.user?.id) { _, _ in editing = nil }
        .overlay {
            if entries.isEmpty {
                Text("기록이 없어").foregroundStyle(.secondary)
            }
        }
        .sheet(item: $editing) { entry in
            AddRecordView(types: type.map { [$0] } ?? [], existing: entry, fixedTypeID: entry.typeID) { updated in
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

    private var type: RecordType? { types.first { $0.id == typeID } }

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
                        .disabled(type == nil || value == nil || !(value?.isFinite ?? false) || (value ?? -1) < 0 || (value ?? 0) > 1_000_000 || (extra ?? 0) < 0 || (extra ?? 0) > 1_000_000)
                }
            }
            .onChange(of: typeID) { _, _ in
                value = nil
                extra = nil
            }
        }
    }

    private func save() {
        guard let type = type, let v = value, v.isFinite, v >= 0, v <= 1_000_000,
              (extra ?? 0) >= 0, (extra ?? 0) <= 1_000_000 else { return }
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
