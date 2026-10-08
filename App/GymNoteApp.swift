import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // 앱을 보고 있을 때도 "휴식 끝" 알림을 띄움
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@main
@MainActor
struct GymNoteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.account)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0
    @State private var selectedDate = Date()
    @State private var showingSettings = false
    @AppStorage("selectedWorkspace") private var workspace = "운동"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Picker("분야", selection: $workspace) {
                    Text("운동").tag("운동")
                    Text("일상").tag("일상")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                Spacer(minLength: 0)
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape").font(.title2)
                }
                .accessibilityLabel("설정")
            }
            .padding(.horizontal).padding(.vertical, 8)
            if workspace == "일상", model.data.activeWorkout != nil {
                Button {
                    workspace = "운동"
                    selectedTab = 0
                } label: {
                    Label("진행 중인 운동으로 돌아가기", systemImage: "figure.strengthtraining.traditional")
                        .font(.subheadline).frame(maxWidth: .infinity).padding(8)
                }
                .background(Color.orange.opacity(0.1))
            }
            TabView(selection: $selectedTab) {
                Group {
                    if workspace == "일상" { DailyTodayView() }
                    else { TodayView() }
                }
                .tabItem { Label("실행", systemImage: "checkmark.circle") }.tag(0)
                Group {
                    if workspace == "일상" { DailyPlansView(selectedDate: $selectedDate) }
                    else { RoutineView(selectedDate: $selectedDate) }
                }
                .tabItem { Label("계획", systemImage: "calendar") }.tag(1)
                Group {
                    if workspace == "일상" { DailyHistoryView() }
                    else { RecordsView() }
                }
                .tabItem { Label("기록", systemImage: "chart.bar") }.tag(2)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .safeAreaInset(edge: .bottom) {
                    Button("닫기") { showingSettings = false }
                        .frame(maxWidth: .infinity).padding().background(.regularMaterial)
                }
        }
        .id(model.selection.generation)
        .tint(.orange)
        // 위젯에서 체크한 내용을 앱으로 다시 불러옴
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.reload()
                account.scheduleSync()
            }
        }
        .task {
            await RestController.requestPermissions()
            model.reload()
            await account.bootstrap()
        }
        .alert("저장소 확인", isPresented: Binding(get: { model.storageError != nil }, set: { if !$0 { model.storageError = nil } })) {
            Button("확인", role: .cancel) { model.storageError = nil }
        } message: { Text(model.storageError ?? "") }
    }
}
