import Charts
import SwiftUI

struct RecordsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    @State private var showingTypes = false
    @State private var tab = RecordsTab.journal
    private enum RecordsTab: Hashable { case records, journal, friends }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("기록 종류", selection: $tab) {
                    Text("운동 일지").tag(RecordsTab.journal)
                    Text("친구").tag(RecordsTab.friends)
                    Text("최고 기록").tag(RecordsTab.records)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                if tab == .journal {
                    WorkoutJournalView()
                } else if tab == .friends {
                    FriendRankingView()
                } else {
                    List {
                        if let message = account.catalogMessage {
                            Text(message).font(.footnote).foregroundStyle(.secondary)
                        }
                        let autoRecords = model.data.exerciseRecords()
                        if account.catalogTypes.filter(\.active).isEmpty {
                            Text("현재 사용할 수 있는 공통 종목이 없어요.").foregroundStyle(.secondary)
                        }
                        ForEach(account.catalogTypes.filter(\.active)) { definition in
                            RecordSection(type: definition.recordType,
                                          auto: model.data.exerciseRecords(for: definition.recordType, in: autoRecords))
                        }
                        ForEach(account.catalogTypes.filter { !$0.active && !model.data.entries($0.recordType).isEmpty }) { definition in
                            RecordSection(type: definition.recordType,
                                          auto: model.data.exerciseRecords(for: definition.recordType, in: autoRecords))
                        }
                        if !legacyTypes.isEmpty {
                            Section {
                                ForEach(legacyTypes) { type in
                                    NavigationLink(type.name) { RecordHistoryView(typeID: type.id) }
                                }
                            } header: { Text("이전 개인 기록") } footer: {
                                Text("기존 기록은 보존됩니다. 새 기록은 실행 탭 또는 지난 운동 기록에서 남겨 주세요.")
                            }
                        }
                        let unlinked = unlinkedAutoRecords(autoRecords)
                        if !unlinked.isEmpty {
                            Section {
                                ForEach(unlinked) { record in AutoRecordRow(record: record) }
                            } header: {
                                Text("운동 일지 자동 기록").font(.title3.bold()).textCase(nil)
                            } footer: {
                                Text("개인 운동 일지에서 계산한 기록이에요. 공통 종목과 같은 이름의 횟수 운동은 해당 종목에 함께 표시됩니다.")
                            }
                        }
                        Section {
                            Button { showingTypes = true } label: {
                                Label(account.canManageCatalog ? "공통 종목 관리" : "공통 종목 안내", systemImage: "list.bullet")
                            }
                        } footer: {
                            Text("운동 일지의 실제 횟수로 한 세트·하루 총량 최고 기록을 자동 계산해요. 위젯은 그날 계획한 운동을 표시하고, 운동이 없는 날에는 사용 중인 공통 종목의 앞 3개를 표시해요.")
                        }
                    }
                }
            }
            .navigationTitle("기록")
            .task(id: tab) { await account.refreshRecordCatalog() }
            .task(id: account.user?.id) { await account.refreshRecordCatalog() }
            .onChange(of: account.user?.id) { _, _ in
                showingTypes = false
            }
            .refreshable { await account.refreshRecordCatalog() }
            .sheet(isPresented: $showingTypes) {
                RecordTypesView()
            }
        }
    }
    private func unlinkedAutoRecords(_ records: [String: ExerciseRecords]) -> [ExerciseRecords] {
        var display = model.data
        display.recordTypes = account.catalogTypes.map(\.recordType)
        return display.unlinkedExerciseRecords(records)
    }

    private var legacyTypes: [RecordType] {
        let commonIDs = Set(account.catalogTypes.map(\.id))
        return model.data.recordTypes.filter { !commonIDs.contains($0.id) && !model.data.entries($0).isEmpty }
    }

}

struct RecordSection: View {
    @Environment(\.gymnoteCompactLayout) private var compact
    @Environment(AppModel.self) private var model
    let type: RecordType
    var auto: ExerciseRecords? = nil

    var body: some View {
        let entries = model.data.entries(type)
        let best = model.data.best(type)

        Section {
            if let auto {
                // 수동 기록과 운동 일지 중 더 높은 한 세트 + 운동 일지의 하루 총량
                let combined = model.data.combinedBestSet(for: type, auto: auto)
                let unit = type.unit.isEmpty ? "회" : type.unit
                RecordValueRow(title: "한 세트 최고",
                               value: combined.map { RecordType.number($0.value) + unit },
                               date: combined?.date,
                               source: combined?.fromJournal == true ? "운동 일지" : "직접 기록")
                RecordValueRow(title: "하루 총량 최고", value: auto.bestDay.map { "\($0.value)\(unit)" },
                               date: auto.bestDay?.date, source: "운동 일지")
            } else {
                (compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout())) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("최고 기록")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(best.map { type.display($0) } ?? "아직 없음")
                            .font(.title2)
                            .bold()
                    }
                    if !compact { Spacer() }
                    if let best = best {
                        Text(best.date, format: .dateTime.year().month().day())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if entries.isEmpty, auto != nil {
                Text("운동 일지 기록은 위 최고 기록에 자동으로 반영돼요. 종목별 기록은 실행 탭에서 남길 수 있어요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !entries.isEmpty {
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
                    Text("실행 탭에서 종목 기록을 남기면 변화가 그래프로 보여요")
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
            }
            .textCase(nil)
        }
    }
}

/// 최고 기록 화면에서는 기존 기록을 조회한다. 갱신은 실행/지난 운동 기록에서만 한다.
struct RecordRow: View {
    let type: RecordType
    let entry: RecordEntry
    var isBest: Bool = false

    var body: some View {
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
        }
    }
}

// MARK: - 전체 기록

struct RecordHistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    let typeID: String

    var body: some View {
        let type = model.data.recordDisplayTypes(catalog: account.catalogTypes).first { $0.id == typeID }
        let entries: [RecordEntry] = type.map { Array(model.data.entries($0).reversed()) } ?? []
        let best = type.flatMap { model.data.best($0) }

        List {
            if let type = type {
                Section {
                    ForEach(entries) { entry in
                        RecordRow(type: type, entry: entry, isBest: entry.id == best?.id)
                    }
                } footer: {
                    Text("기록 갱신은 실행 탭 또는 지난 운동 기록에서 할 수 있어요.")
                }
            }
        }
        .navigationTitle(type?.name ?? "기록")
        .overlay {
            if entries.isEmpty {
                Text("기록이 없어").foregroundStyle(.secondary)
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
    let onSave: (RecordEntry) -> Bool

    @State private var typeID: String
    @State private var value: Double?
    @State private var extra: Int?
    @State private var date: Date
    @State private var saveFailed = false

    /// fixedTypeID를 주면 그 종목으로 고정 (종목 선택 칸 숨김)
    init(types: [RecordType], existing: RecordEntry? = nil, fixedTypeID: String? = nil,
         onSave: @escaping (RecordEntry) -> Bool) {
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
    private var validInput: Bool {
        guard let type, let value, type.acceptsValue(value), (0...1_000_000).contains(value) else { return false }
        return (0...1_000_000).contains(extra ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                if saveFailed { Text("저장하지 못했어요. 입력 내용을 확인하고 다시 시도해 주세요.").foregroundStyle(.red) }
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
                                    .keyboardType(type.requiresWholeValue ? .numberPad : .decimalPad)
                                Text(type.unit)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        DatePicker("날짜", selection: $date, displayedComponents: .date)
                    } footer: {
                        if type.requiresWholeValue { Text("횟수와 라운드는 소수점 없이 정수로 입력해 주세요.") }
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
                        .disabled(!validInput)
                }
            }
            .onChange(of: typeID) { _, _ in
                value = nil
                extra = nil
            }
        }
        .protectEditingNavigation()
    }

    private func save() {
        guard validInput, let type, let v = value else { return }
        var entry = RecordEntry(typeID: type.id, date: date, value: v)
        if let existing = existing { entry.id = existing.id }
        if type.style == .rounds {
            // 추가 횟수가 라운드당 횟수를 넘으면 라운드로 넘김
            let perRound = max(type.repsPerRound, 1)
            let total = Int(v) * perRound + max(extra ?? 0, 0)
            entry.value = Double(total / perRound)
            entry.extraReps = total % perRound
        }
        guard onSave(entry) else { saveFailed = true; return }
        dismiss()
    }
}

/// 최고 기록 한 줄: 제목, 값, 달성 날짜, 출처
struct RecordValueRow: View {
    let title: String
    let value: String?
    let date: Date?
    var source: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value ?? "아직 없음").font(.title2).bold()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let date { Text(date, format: .dateTime.year().month().day()).foregroundStyle(.secondary) }
                if value != nil, let source { Text(source).font(.caption2).foregroundStyle(.tertiary) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 수동 종목이 없는 운동의 자동 기록
struct AutoRecordRow: View {
    let record: ExerciseRecords

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(record.name).font(.headline)
            HStack(spacing: 16) {
                summary("한 세트 최고", record.bestSet)
                summary("하루 총량 최고", record.bestDay)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func summary(_ title: String, _ value: AutoRecord?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.map { "\($0.value)회" } ?? "–").font(.title3.bold())
            if let value { Text(value.date, format: .dateTime.month().day()).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
