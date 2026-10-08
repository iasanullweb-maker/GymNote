import Charts
import SwiftUI

struct RecordsView: View {
    @Environment(AppModel.self) private var model
    @State private var showingAdd = false
    @State private var prMessage: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(RecordKind.allCases) { kind in
                    RecordSection(kind: kind)
                }
            }
            .navigationTitle("기록")
            .toolbar {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddRecordView { entry in
                    if model.addRecord(entry) {
                        prMessage = "\(entry.kind.label) \(entry.display)"
                    }
                }
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
    let kind: RecordKind

    var body: some View {
        let entries = model.data.entries(kind)
        let yLabel: String = kind == .cindy ? "총 반복" : "횟수"

        Section(kind.label) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("최고 기록")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.data.best(kind)?.display ?? "아직 없음")
                        .font(.title2)
                        .bold()
                }
                Spacer()
                if let best = model.data.best(kind) {
                    Text(best.date, format: .dateTime.month().day())
                        .foregroundStyle(.secondary)
                }
            }

            if entries.count >= 2 {
                Chart(entries) { entry in
                    LineMark(
                        x: .value("날짜", entry.date),
                        y: .value(yLabel, entry.score)
                    )
                    PointMark(
                        x: .value("날짜", entry.date),
                        y: .value(yLabel, entry.score)
                    )
                }
                .foregroundStyle(.orange)
                .frame(height: 140)
            }

            ForEach(Array(entries.reversed().prefix(5))) { entry in
                HStack {
                    Text(entry.date, format: .dateTime.month().day())
                    Spacer()
                    Text(entry.display)
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

struct AddRecordView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (RecordEntry) -> Void

    @State private var kind: RecordKind = .pushup
    @State private var value: Int?
    @State private var extra: Int?
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Picker("종목", selection: $kind) {
                    ForEach(RecordKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                Section {
                    TextField(kind == .cindy ? "라운드" : "횟수", value: $value, format: .number)
                        .keyboardType(.numberPad)
                    if kind == .cindy {
                        TextField("추가 횟수 (0~29)", value: $extra, format: .number)
                            .keyboardType(.numberPad)
                    }
                    DatePicker("날짜", selection: $date, displayedComponents: .date)
                } footer: {
                    Text(kind.hint)
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
        }
    }

    private func save() {
        guard let v = value, v >= 0 else { return }
        var rounds = v
        var reps = 0
        if kind == .cindy {
            // 추가 횟수가 30 이상이면 라운드로 넘김
            let total = v * RecordEntry.cindyRepsPerRound + max(extra ?? 0, 0)
            rounds = total / RecordEntry.cindyRepsPerRound
            reps = total % RecordEntry.cindyRepsPerRound
        }
        onSave(RecordEntry(kind: kind, date: date, value: rounds, extraReps: reps))
        dismiss()
    }
}
