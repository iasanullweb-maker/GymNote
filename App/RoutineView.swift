import SwiftUI

struct RoutineView: View {
    @Environment(AppModel.self) private var model

    /// 월요일부터 보여줌 (0=일)
    private let order = [1, 2, 3, 4, 5, 6, 0]

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            List {
                Section("요일별 루틴") {
                    ForEach(order, id: \.self) { i in
                        let plan = model.data.week[i]
                        NavigationLink {
                            DayEditor(index: i)
                        } label: {
                            HStack(spacing: 12) {
                                Text(DayKey.weekdayNames[i])
                                    .bold()
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(plan.isRestDay ? "휴식" : plan.title)
                                    if !plan.isRestDay {
                                        Text(plan.exercises.map(\.name).joined(separator: ", "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("설정") {
                    Stepper(
                        "위젯 휴식 버튼: \(model.data.defaultRest)초",
                        value: $model.data.defaultRest,
                        in: 15...600,
                        step: 15
                    )
                }

                Section {
                    LabeledContent("위젯 공유 저장소", value: SharedStore.diagnostics)
                        .font(.caption)
                } header: {
                    Text("진단")
                } footer: {
                    Text("'연결 안 됨'이면 위젯이 앱 데이터를 못 읽어. 이 화면을 캡처해서 보여줘.")
                }
            }
            .navigationTitle("루틴")
        }
    }
}

struct DayEditor: View {
    @Environment(AppModel.self) private var model
    let index: Int

    var body: some View {
        @Bindable var model = model

        Form {
            Section("이름") {
                TextField("예: 상체", text: $model.data.week[index].title)
            }

            Section {
                ForEach($model.data.week[index].exercises) { $exercise in
                    NavigationLink {
                        ExerciseEditor(exercise: $exercise)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                            Text("\(exercise.sets)세트 · \(exercise.detail) · 휴식 \(exercise.restSeconds)초")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    model.data.week[index].exercises.remove(atOffsets: offsets)
                }
                .onMove { source, destination in
                    model.data.week[index].exercises.move(fromOffsets: source, toOffset: destination)
                }

                Button {
                    model.data.week[index].exercises.append(
                        Exercise(name: "새 운동", sets: 3, detail: "10회", restSeconds: model.data.defaultRest)
                    )
                } label: {
                    Label("운동 추가", systemImage: "plus")
                }
            } header: {
                Text("운동")
            } footer: {
                Text("운동을 모두 지우면 휴식일이 돼. 왼쪽으로 밀어서 삭제, 편집 버튼으로 순서 변경.")
            }
        }
        .navigationTitle("\(DayKey.weekdayNames[index])요일")
        .toolbar { EditButton() }
    }
}

struct ExerciseEditor: View {
    @Binding var exercise: Exercise

    var body: some View {
        Form {
            TextField("운동 이름", text: $exercise.name)
            Stepper("세트: \(exercise.sets)", value: $exercise.sets, in: 1...20)
            TextField("세부 (예: 10회, 1분)", text: $exercise.detail)
            Stepper("세트 사이 휴식: \(exercise.restSeconds)초", value: $exercise.restSeconds, in: 0...600, step: 15)
        }
        .navigationTitle(exercise.name)
    }
}
