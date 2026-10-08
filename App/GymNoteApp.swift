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

    var body: some View {
        Group {
            if !account.initialized || account.connection == .checking {
                ProgressView("기기 기록을 불러오는 중…")
            } else if account.showsWelcome {
                AccountView(welcome: true)
            } else {
                mainTabs
            }
        }
        .tint(.orange)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.reload()
                account.scheduleSync()
            }
        }
        .task {
            await account.bootstrap()
            model.reload()
            await RestController.requestPermissions()
        }
        .alert("저장소 확인", isPresented: Binding(get: { model.storageError != nil }, set: { if !$0 { model.storageError = nil } })) {
            Button("확인", role: .cancel) { model.storageError = nil }
        } message: { Text(model.storageError ?? "") }
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem { Label("운동", systemImage: "figure.strengthtraining.traditional") }
                .tag(0)
            RoutineView()
                .tabItem { Label("계획", systemImage: "calendar") }
                .tag(1)
            RecordsView()
                .tabItem { Label("기록", systemImage: "trophy") }
                .tag(2)
            AccountView()
                .tabItem { Label("설정", systemImage: "gearshape") }
                .tag(3)
        }
        .id(model.selection.generation)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !account.isOnline {
                Label("오프라인 · 기기 기록으로 계속 진행", systemImage: "wifi.slash")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.thinMaterial)
            }
        }
    }
}
