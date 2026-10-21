import SwiftUI
import UserNotifications

/// 설정 탭: 휴식 타이머, 계정(시트로 열기), 진단
struct SettingsView: View {
    static let restRange = 5...600
    static let stepRange = 5...120
    /// 예: "버전 0.1.104 (104)". Info.plist의 CFBundleShortVersionString·CFBundleVersion(빌드 때 Actions가 채움).
    static let appVersion: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "버전 \(version) (\($0))" } ?? "버전 \(version)"
    }()

    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    @AppStorage(CoachmarkHistory.key) private var completedCoachmarks = ""
    @State private var showingAccount = false
    @AppStorage(WorkoutStartAnimationStyle.storageKey) private var startStyle = WorkoutStartAnimationStyle.defaultStyle
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    /// 기기별 설정. 같은 계정의 다른 기기와 공유하지 않는다.
    @AppStorage(DailyReminderScheduler.devicePreferenceKey) private var remindersOnThisDevice = false
    @Environment(\.openURL) private var openURL
    /// 설치된 앱의 AltStore 서명 만료 상태. 개발/시뮬레이터 빌드에서는 nil.
    @State private var signing: SigningExpiry.Status? = SigningExpiryMonitor.status()

    private var signingDescription: String {
        guard let signing else { return "확인 불가(개발 빌드)" }
        let date = signing.expiration.formatted(.dateTime.month().day().hour().minute())
        return signing.level == .expired ? "\(date) · 만료됨" : "\(date) · \(SigningExpiry.remainingText(signing.remaining)) 남음"
    }

    /// 만료 48시간 이내·만료 시 설정 맨 위에 보이는 갱신 안내.
    @ViewBuilder private func signingWarningSection(_ signing: SigningExpiry.Status) -> some View {
        Section {
            Label(signing.level == .expired
                  ? "앱 서명이 만료됐어요"
                  : "앱 서명 만료까지 \(SigningExpiry.remainingText(signing.remaining))",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Button("AltStore 열기") {
                if let url = URL(string: "altstore://") { openURL(url) }
            }
        } header: {
            Text("AltStore 갱신 필요")
        } footer: {
            Text("노트북에서 AltServer와 iTunes를 켜고, 학교 Wi-Fi라면 노트북 VPN을 켠 뒤 iPad를 USB로 연결해요. AltStore → My Apps → Refresh All. 안 되면 노트북에서 'AltStore 진단.cmd'를 실행해요.")
        }
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                if let signing, signing.level != .ok {
                    signingWarningSection(signing)
                }
                Section("저장 상태") {
                    Label(account.modeDescription, systemImage: account.isOnline ? "icloud" : "wifi.slash")
                }
                Section {
                    Stepper("세트 사이 휴식: \(RestDuration.text(seconds: model.data.defaultRest))", value: $model.data.defaultRest,
                            in: Self.restRange, step: 5)
                        .coachmarkTarget("settings.rest")
                    Stepper("−/+ 버튼 간격: \(RestDuration.text(seconds: model.data.restStep))", value: $model.data.restStep,
                            in: Self.stepRange, step: 5)
                    Toggle("휴식 끝 알림 소리", isOn: $model.data.restSound)
                } header: {
                    Text("휴식 타이머")
                } footer: {
                    Text("세트 완료를 누르면 모든 운동에 이 휴식이 자동으로 시작돼. '−/+ 버튼 간격'은 운동 탭 휴식 타이머 옆 −/+를 한 번 누를 때 바뀌는 시간이야. 5초 단위, 최소 5초. 소리를 끄면 휴식이 끝날 때 알림 배너만 떠.")
                }

                Section {
                    Picker("운동 시작 애니메이션", selection: $startStyle) {
                        ForEach(WorkoutStartAnimationStyle.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("화면")
                } footer: {
                    Text("‘버튼이 바로 변신’은 누른 운동 시작 버튼이 아래 운동 중 바로 날아가 바뀌어요. ‘아래에서 올라오기’는 바가 화면 아래에서 올라와요. 이 기기에만 적용되고, 동작 줄이기를 켜면 둘 다 부드럽게 나타나기만 해요.")
                }

                Section {
                    Button("튜토리얼 다시 보기") { completedCoachmarks = "" }
                } header: {
                    Text("사용 안내")
                } footer: {
                    Text("각 탭의 짧은 안내를 이 기기에서 다시 표시해요.")
                }

                dailyReminderSection

                Section("계정") {
                    if account.canManageCatalog {
                        Label("관리자 계정", systemImage: "checkmark.shield.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                    }
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

                Section {
                    LabeledContent("앱 서명 만료", value: signingDescription)
                        .font(.caption)
                    LabeledContent("위젯 공유 저장소", value: SharedStore.diagnostics)
                        .font(.caption)
                } header: {
                    Text("진단")
                } footer: {
                    // 설정 맨 아래 작은 글씨: 설치된 앱 버전(빌드 번호). AltStore 버전과 비교할 때 쓴다.
                    Text("헬스노트 \(Self.appVersion)")
                        .font(.caption2)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("설정")
            .task(id: account.user?.id) { await account.refreshRecordCatalog() }
            .task { notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
            .task { signing = SigningExpiryMonitor.status() }
            .sheet(isPresented: $showingAccount, onDismiss: { account.closeAccountScreen() }) {
                AccountView()
                    .environment(model)
                    .environment(account)
            }
        }
    }

    @ViewBuilder private var dailyReminderSection: some View {
        @Bindable var model = model
        Section {
            Toggle("일상 알림", isOn: $model.data.dailyReminders.enabled)
            if model.data.dailyReminders.enabled {
                Toggle("이 기기에서 알림 받기", isOn: $remindersOnThisDevice)
                    .onChange(of: remindersOnThisDevice) { _, _ in model.refreshReminders() }
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
                 ? "기기 설정에서 헬스노트 알림이 꺼져 있어 울리지 않아요."
                 : "항목별 알림 시간은 일상 추가·편집에서 정해요. 아침 요약은 그날 할 일상을, 저녁 확인은 아직 끝내지 않은 일상이 있을 때만 알려요. 앞으로 2주치를 미리 예약하고 앱을 열 때마다 다시 채워요. '이 기기에서 알림 받기'는 기기마다 따로 정해서, 같은 계정을 쓰는 여러 기기 중 켠 기기에서만 울려요.")
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
