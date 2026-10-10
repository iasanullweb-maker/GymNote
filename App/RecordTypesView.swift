import SwiftUI

struct RecordTypesView: View {
    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var editing: CatalogRecordType?

    var body: some View {
        NavigationStack {
            List {
                if let message = account.catalogMessage {
                    Text(message).foregroundStyle(.secondary)
                }
                Section {
                    ForEach(account.catalogTypes) { type in
                        Button {
                            if account.canManageCatalog { editing = type }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(type.name).foregroundStyle(.primary)
                                Text(type.active ? "사용 중 · 순서 \(type.position + 1)" : "사용 중단 · 과거 기록 보존")
                                    .font(.caption).foregroundStyle(.secondary)
                                if !type.hint.isEmpty {
                                    Text(type.hint).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(!account.canManageCatalog || account.busy || account.catalogLoading)
                    }
                    if account.canManageCatalog {
                        Button("공통 종목 추가", systemImage: "plus") {
                            editing = CatalogRecordType(id: "common-" + UUID().uuidString.lowercased(),
                                name: "", unit: "회", style: .count, repsPerRound: 30,
                                lowerIsBetter: false, hint: "", active: true,
                                position: min((account.catalogTypes.map(\.position).max() ?? -1) + 1, 9999), revision: 0)
                        }.disabled(account.busy || account.catalogLoading)
                    }
                } footer: {
                    Text("공통 종목은 운동 목록·계획·운동 일지·최고 기록에서 함께 사용하며 관리자가 관리합니다. 개인별 세트·횟수는 운동을 가져온 뒤 설정하세요. 단위·수행 조건·계산 규칙을 바꿀 때는 새 종목을 만들어 과거 기록의 비교 기준을 유지합니다.")
                }
                if let date = account.catalogFetchedAt {
                    Text("목록 갱신: \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("기본 공통 목록입니다. 서버 연결 후 최신 목록이 적용됩니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(account.canManageCatalog ? "공통 종목 관리" : "공통 종목 안내")
            .refreshable { await account.refreshRecordCatalog() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("새로고침") { Task { await account.refreshRecordCatalog() } }
                        .disabled(account.catalogLoading || account.busy || !account.isOnline)
                }
                ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } }
            }
            .sheet(item: $editing) { type in CatalogTypeEditor(type: type) }
        }
    }
}

struct CatalogTypeEditor: View {
    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State var type: CatalogRecordType
    @State private var saving = false

    private var isNew: Bool { type.revision == 0 }
    private var valid: Bool {
        let name = type.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= 80 && type.unit.count <= 20 && type.hint.count <= 1000
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("표시") {
                    TextField("종목 이름", text: $type.name)
                    TextField("수행 규칙 및 설명", text: $type.hint, axis: .vertical)
                    Stepper("표시 순서: \(type.position + 1)", value: $type.position, in: 0...9999)
                    Toggle("새 운동 선택·기록 입력 허용", isOn: $type.active)
                }
                Section {
                    Picker("기록 방식", selection: $type.style) {
                        Text("숫자").tag(RecordType.Style.count)
                        Text("라운드 + 횟수").tag(RecordType.Style.rounds)
                    }
                    TextField("단위 (회, kg, 초)", text: $type.unit)
                    Toggle("낮을수록 좋은 기록", isOn: $type.lowerIsBetter)
                    if type.style == .rounds {
                        Stepper("라운드당 횟수: \(type.repsPerRound)", value: $type.repsPerRound, in: 1...500)
                    }
                } header: { Text("비교 규칙") } footer: {
                    Text(isNew ? "생성 후 비교 규칙은 고정됩니다. 수행 조건을 설명에 명확히 적어 주세요."
                         : "비교 규칙은 바꿀 수 없습니다. 설명은 오탈자 정정에 사용하고, 수행 조건이 바뀌면 새 종목을 만들어 주세요.")
                }
                .disabled(!isNew)
                if let message = account.catalogMessage {
                    Text(message).foregroundStyle(.red)
                }
            }
            .disabled(saving)
            .navigationTitle(isNew ? "공통 종목 추가" : "공통 종목 수정")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "저장 중…" : "저장") {
                        type.name = type.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        saving = true
                        Task {
                            if await account.saveCatalogType(type) { dismiss() }
                            saving = false
                        }
                    }.disabled(!valid || saving || account.busy || account.catalogLoading || !account.canManageCatalog)
                }
            }
        }
        .protectEditingNavigation()
    }
}
