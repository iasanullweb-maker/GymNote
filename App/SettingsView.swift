import SwiftUI

/// 설정 탭: 휴식 타이머, 계정(시트로 열기), 진단
struct SettingsView: View {
    static let restRange = 5...600
    static let stepRange = 5...120

    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    @State private var showingAccount = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Stepper("세트 사이 휴식: \(model.data.defaultRest)초", value: $model.data.defaultRest,
                            in: Self.restRange, step: 5)
                    Stepper("−/+ 버튼 간격: \(model.data.restStep)초", value: $model.data.restStep,
                            in: Self.stepRange, step: 5)
                    Toggle("휴식 끝 알림 소리", isOn: $model.data.restSound)
                } header: {
                    Text("휴식 타이머")
                } footer: {
                    Text("세트 완료를 누르면 모든 운동에 이 휴식이 자동으로 시작돼. '−/+ 버튼 간격'은 운동 탭 휴식 타이머 옆 −/+를 한 번 누를 때 바뀌는 시간이야. 5초 단위, 최소 5초. 소리를 끄면 휴식이 끝날 때 알림 배너만 떠.")
                }

                Section("계정") {
                    Button { showingAccount = true } label: {
                        HStack {
                            Label(account.user?.email ?? "로그인 안 함 (이 기기에 저장 중)", systemImage: "person.crop.circle")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Section("진단") {
                    LabeledContent("위젯 공유 저장소", value: SharedStore.diagnostics)
                        .font(.caption)
                }
            }
            .navigationTitle("설정")
            .sheet(isPresented: $showingAccount) {
                AccountView()
                    .environment(model)
                    .environment(account)
                    .safeAreaInset(edge: .bottom) {
                        Button("닫기") { showingAccount = false }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.regularMaterial)
                    }
            }
        }
    }
}
