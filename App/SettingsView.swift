import SwiftUI

/// 설정 탭: 휴식 타이머, 계정(시트로 열기), 진단
struct SettingsView: View {
    static let restStep = 15
    static let restRange = 15...600

    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    @State private var showingAccount = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("저장 상태") {
                    Label(account.modeDescription, systemImage: account.isOnline ? "icloud" : "wifi.slash")
                }
                Section {
                    Stepper("기본 휴식: \(model.data.defaultRest)초", value: $model.data.defaultRest,
                            in: Self.restRange, step: Self.restStep)
                    Toggle("휴식 끝 알림 소리", isOn: $model.data.restSound)
                } header: {
                    Text("휴식 타이머")
                } footer: {
                    Text("운동 탭의 휴식 타이머 옆 −/+로도 바꿀 수 있어. 소리를 끄면 휴식이 끝날 때 알림 배너만 떠.")
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
