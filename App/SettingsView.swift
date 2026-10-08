import SwiftUI
import UserNotifications

/// 설정 탭: 휴식 타이머, 계정(시트로 열기), 진단
struct SettingsView: View {
    static let restRange = 5...600
    static let stepRange = 5...120

    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    @State private var showingAccount = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("저장 상태") {
                    Label(account.modeDescription, systemImage: account.isOnline ? "icloud" : "wifi.slash")
                }
                Section {
                    Stepper("세트 사이 휴식: \(RestDuration.text(seconds: model.data.defaultRest))", value: $model.data.defaultRest,
                            in: Self.restRange, step: 5)
                    Stepper("−/+ 버튼 간격: \(RestDuration.text(seconds: model.data.restStep))", value: $model.data.restStep,
                            in: Self.stepRange, step: 5)
                    Toggle("휴식 끝 알림 소리", isOn: $model.data.restSound)
                } header: {
                    Text("휴식 타이머")
                } footer: {
                    Text("세트 완료를 누르면 모든 운동에 이 휴식이 자동으로 시작돼. '−/+ 버튼 간격'은 운동 탭 휴식 타이머 옆 −/+를 한 번 누를 때 바뀌는 시간이야. 5초 단위, 최소 5초. 소리를 끄면 휴식이 끝날 때 알림 배너만 떠.")
                }

                dailyReminderSection

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
            .task { notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
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

    @ViewBuilder private var dailyReminderSection: some View {
        @Bindable var model = model
        Section {
            Toggle("일상 알림", isOn: $model.data.dailyReminders.enabled)
            if model.data.dailyReminders.enabled {
                Toggle("알림 소리", isOn: $model.data.dailyReminders.sound)
                optionalTime("아침 요약", \.morningSummary, default: ReminderTime(hour: 8, minute: 0))
                optionalTime("저녁 확인", \.eveningCheck, default: ReminderTime(hour: 21, minute: 0))
            }
            if notificationStatus == .denied {
                Button("설정 앱에서 알림 허용하기") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
            }
        } header: {
            Text("일상 알림")
        } footer: {
            Text(notificationStatus == .denied
                 ? "아이패드 설정에서 헬스노트 알림이 꺼져 있어 울리지 않아요."
                 : "항목별 알림 시간은 일상 추가·편집에서 정해요. 아침 요약은 그날 할 일상을, 저녁 확인은 아직 끝내지 않은 일상이 있을 때만 알려요. 앞으로 2주치를 미리 예약하고 앱을 열 때마다 다시 채워요.")
        }
    }

    /// 켜면 시간 선택이 나타나는 알림 행 (아침 요약·저녁 확인)
    @ViewBuilder
    private func optionalTime(_ title: String, _ path: WritableKeyPath<DailyReminderSettings, ReminderTime?>,
                              default fallback: ReminderTime) -> some View {
        let isOn = Binding(
            get: { model.data.dailyReminders[keyPath: path] != nil },
            set: { model.data.dailyReminders[keyPath: path] = $0 ? fallback : nil })
        Toggle(title, isOn: isOn)
        if let time = model.data.dailyReminders[keyPath: path] {
            DatePicker("\(title) 시간", selection: Binding(
                get: { time.pickerDate },
                set: { model.data.dailyReminders[keyPath: path] = ReminderTime($0) }),
                displayedComponents: .hourAndMinute)
        }
    }
}
