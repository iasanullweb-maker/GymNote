import SwiftUI
import UIKit

struct ManualWorkoutView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.gymnoteCompactLayout) private var compact
    @AppStorage private var savedDraft: String
    @State private var draft = ManualWorkoutDraft()
    @State private var loaded = false
    @State private var saveFailed = false
    let initialDate: Date
    let onSave: (Date) -> Void

    init(date: Date, userID: UUID?, onSave: @escaping (Date) -> Void) {
        initialDate = date
        self.onSave = onSave
        _savedDraft = AppStorage(wrappedValue: "", ManualWorkoutDraft.storageKey(userID: userID))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("운동한 날짜", selection: $draft.date, in: ...Date(), displayedComponents: .date)
                    TextField("일지 제목", text: $draft.title)
                } footer: {
                    Text("운동을 마친 뒤 한 번에 기록하세요. 입력 내용은 이 기기에 임시 저장돼요.")
                }
                Section("불러오기 · 현재 입력에 추가") {
                    Button("선택한 날짜의 루틴") {
                        let plan = model.data.plan(for: draft.date)
                        if draft.moves.isEmpty { draft.title = plan.title }
                        for exercise in plan.exercises { draft.append(exercise) }
                    }.disabled(model.data.plan(for: draft.date).isRestDay)
                    Menu("이전 운동 일지") {
                        ForEach(model.data.workouts.sorted { $0.startedAt > $1.startedAt }) { workout in
                            Button("\(workout.startedAt.formatted(.dateTime.year().month().day())) · \(workout.plan.title)") {
                                if draft.moves.isEmpty { draft.title = workout.plan.title }
                                for exercise in workout.plan.exercises { draft.append(exercise, session: workout) }
                            }
                        }
                    }.disabled(model.data.workouts.isEmpty)
                    Menu("운동 목록") {
                        ForEach(model.data.exerciseLibrary) { exercise in
                            Button(exercise.name) { draft.append(exercise) }
                        }
                    }.disabled(model.data.exerciseLibrary.isEmpty)
                }
                ForEach($draft.moves) { $move in
                    Section {
                        TextField("운동 이름", text: $move.name)
                        TextField("계획 또는 시간 (예: 10회, 1분)", text: $move.detail)
                        ForEach($move.sets) { $entry in
                            VStack(alignment: .leading, spacing: 8) {
                                let index = move.sets.firstIndex { $0.id == entry.id } ?? 0
                                HStack {
                                    Text("\(index + 1)세트").font(.subheadline.bold())
                                    Spacer()
                                    Button(role: .destructive) { move.sets.removeAll { $0.id == entry.id } } label: {
                                        Image(systemName: "minus.circle")
                                    }.buttonStyle(.borderless).accessibilityLabel("\(index + 1)세트 삭제")
                                }
                                (compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout())) {
                                    HStack {
                                        TextField("실제 횟수", text: $entry.reps).keyboardType(.numberPad)
                                            .accessibilityLabel("\(index + 1)세트 실제 횟수")
                                        Text("회").foregroundStyle(.secondary)
                                    }
                                    HStack {
                                        TextField("무게 (선택)", text: $entry.weight).keyboardType(.decimalPad)
                                            .accessibilityLabel("\(index + 1)세트 무게 kg")
                                        Text("kg").foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        Button("마지막 세트 복사 · 추가") {
                            var entry = move.sets.last ?? ManualWorkoutDraft.SetEntry()
                            entry.id = UUID()
                            move.sets.append(entry)
                        }.disabled(move.sets.count >= 100)
                        Button("운동 삭제", role: .destructive) { draft.moves.removeAll { $0.id == move.id } }
                    } header: { Text(move.name.isEmpty ? "새 운동" : move.name) }
                }
                Section {
                    Button { draft.moves.append(ManualWorkoutDraft.Move()) } label: {
                        Label("직접 운동 추가", systemImage: "plus.circle")
                    }
                } footer: {
                    Text("모든 세트를 완료한 기록으로 저장해요. 횟수는 0~9999회, 무게는 0~9999kg까지 입력하세요. 시간 운동은 계획 또는 시간을 적고 횟수를 비워 둘 수 있어요.")
                }
                Section("저장할 내용") {
                    Text("운동 \(draft.moves.count)개 · \(draft.moves.reduce(0) { $0 + $1.sets.count })세트")
                    Button("한 번에 저장", action: save).disabled(!draft.isValid)
                }
            }
            .navigationTitle("지난 운동 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", action: save).disabled(!draft.isValid)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("입력 완료") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
            }
            .onAppear {
                guard !loaded else { return }
                if let raw = savedDraft.data(using: .utf8), let saved = try? JSONDecoder().decode(ManualWorkoutDraft.self, from: raw) {
                    draft = saved
                } else {
                    draft.date = min(initialDate, Date())
                }
                loaded = true
            }
            .onChange(of: draft) { _, value in
                guard loaded, let raw = try? JSONEncoder().encode(value) else { return }
                savedDraft = String(data: raw, encoding: .utf8) ?? ""
            }
            .alert("저장하지 못했어요", isPresented: $saveFailed) {
                Button("확인", role: .cancel) { }
            } message: { Text("입력 내용은 남아 있어요. 기기를 잠금 해제하고 다시 시도해 주세요.") }
        }
        .protectEditingNavigation()
    }

    private func save() {
        guard let session = draft.session() else { return }
        model.data.workouts.append(session)
        guard model.data.workouts.contains(where: { $0.id == session.id }) else { saveFailed = true; return }
        savedDraft = ""
        onSave(draft.date)
        dismiss()
    }
}
