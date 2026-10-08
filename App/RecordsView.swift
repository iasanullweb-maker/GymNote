import Charts
import SwiftUI

struct RecordsView: View {
    @Environment(AppModel.self) private var model
    @State private var showingAdd = false
    @State private var showingTypes = false
    @State private var prMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if model.data.recordTypes.isEmpty {
                    Text("종목이 없어. 오른쪽 위 '종목 편집'에서 추가해 줘.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.data.recordTypes) { type in
                    RecordSection(type: type)
                }
            }
            .navigationTitle("기록")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("종목 편집") { showingTypes = true }
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(model.data.recordTypes.isEmpty)
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddRecordView(types: model.data.recordTypes) { entry in
                    if model.addRecord(entry), let type = model.data.recordType(entry.typeID) {
                        prMessage = "\(type.name) \(type.display(entry))"
                    }
                }
            }
            .sheet(isPresented: $showingTypes) {
                RecordTypesView()
                    .environment(model)
            }
            .alert(
                "🎉 신기록!",
                isPresented: Binding(
                    get: { prMessage != nil },
                    set: { if !$0 { prMessage = nil } }
                )
            ) {
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

    var body: some View {
        let entries = model.data.entries(type)
        let best = model.data.best(type)
        let yLabel = type.style == .rounds ? "총 반복" : "기록"

        Section(type.name) {
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
                    Text(best.date, format: .dateTime.month().day())
                        .foregroundStyle(.secondary)
                }
            }

            if entries.count >= 2 {
                Chart(entries) { entry in
                    LineMark(
                        x: .value("날짜", entry.date),
                        y: .value(yLabel, type.score(entry))
                    )
                    PointMark(
                        x: .value("날짜", entry.date),
                        y: .value(yLabel, type.score(entry))
                    )
                }
                .foregroundStyle(.orange)
                .frame(height: 140)
            }

            ForEach(Array(entries.reversed().prefix(5))) { entry in
                HStack {
                    Text(entry.date, format: .dateTime.month().day())
                    Spacer()
                    Text(type.display(entry))
                }
                .swipeActions {
                    Button("삭제", role: .destructive) {
                        model.data.records.removeAll { $0.id == entry.id }
                    }
                }
            }
        }
    }
}

// MARK: - 기록 추가

struct AddRecordView: View {
    @Environment(\.dismiss) private var dismiss
    let types: [RecordType]
    let onSave: (RecordEntry) -> Void

    @State private var typeID: String = ""
    @State private var value: Double?
    @State private var extra: Int?
    @State private var date = Date()

    private var type: RecordType? { types.first { $0.id == typeID } ?? types.first }

    var body: some View {
        NavigationStack {
            Form {
                Picker("종목", selection: $typeID) {
                    ForEach(types) { t in
                        Text(t.name).tag(t.id)
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
            .navigationTitle("기록 추가")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .disabled((value ?? -1) < 0)
                }
            }
            .onAppear {
                if typeID.isEmpty { typeID = types.first?.id ?? "" }
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
                        let new = RecordType(name: "새 종목")
                        model.data.recordTypes.append(new)
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
        }
    }

    private func summary(_ type: RecordType) -> String {
        if type.style == .rounds { return "라운드 + 추가 횟수 · 라운드당 \(type.repsPerRound)회" }
        var text = type.unit.isEmpty ? "숫자" : "단위: \(type.unit)"
        if type.lowerIsBetter { text += " · 낮을수록 좋음" }
        return text
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
