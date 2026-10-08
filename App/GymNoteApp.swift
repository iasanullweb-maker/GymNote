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
struct GymNoteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("운동", systemImage: "figure.strengthtraining.traditional") }
            RoutineView()
                .tabItem { Label("루틴", systemImage: "calendar") }
            RecordsView()
                .tabItem { Label("기록", systemImage: "trophy") }
        }
        .tint(.orange)
        // 데이터가 바뀌면 자동 저장 + 위젯 새로고침
        .onChange(of: model.data) { _, newValue in
            SharedStore.save(newValue)
        }
        // 위젯에서 체크한 내용을 앱으로 다시 불러옴
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.reload() }
        }
        .task {
            await RestController.requestPermissions()
            model.reload()
        }
    }
}
