import Combine
import SwiftUI
import UserNotifications

extension Notification.Name {
    /// 앱 화면 밖(알림 버튼 등)에서 저장소가 바뀌었음을 화면에 알린다.
    static let gymnoteStoreChanged = Notification.Name("gymnote.storeChanged")
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        DailyReminderScheduler.registerCategories()
        return true
    }

    /// 일상 알림 버튼: '완료'는 앱을 열지 않고 기록, '10분 뒤 다시'는 한 번 더 예약, 알림을 누르면 일상 화면으로.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        guard [DailyReminderScheduler.itemCategory, DailyReminderScheduler.summaryCategory].contains(content.categoryIdentifier)
        else { return }
        let info = content.userInfo
        switch response.actionIdentifier {
        case DailyReminderScheduler.doneAction:
            guard let id = (info["itemID"] as? String).flatMap(UUID.init(uuidString:)),
                  let day = info["day"] as? String, let generation = info["generation"] as? String else { return }
            if let saved = try? SharedStore.completeDailyFromNotification(itemID: id, day: day, generation: generation) {
                await DailyReminderScheduler.apply(data: saved.0, generation: saved.1)
                await DailyReminderScheduler.removeDelivered(itemID: id, day: day)
                NotificationCenter.default.post(name: .gymnoteStoreChanged, object: nil)
            }
        case DailyReminderScheduler.snoozeAction:
            await DailyReminderScheduler.snooze(content)
        case UNNotificationDefaultActionIdentifier:
            UserDefaults.standard.set("일상", forKey: "selectedWorkspace")
        default:
            break
        }
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
    @AppStorage("selectedWorkspace") private var workspace = "운동"

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
                Task { await account.refreshRecordCatalog() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .gymnoteStoreChanged).receive(on: RunLoop.main)) { _ in
            model.reload()
            account.scheduleSync()
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
        VStack(spacing: 0) {
            WorkspaceSwitcher(selection: $workspace)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            if model.data.activeWorkout != nil || model.restEnd != nil {
                WorkoutStatusBanner(
                    startedAt: model.data.activeWorkout?.startedAt,
                    restStart: model.restStart, restEnd: model.restEnd,
                    finishTitle: model.workoutProgress.done == 0 ? "시작 취소" : "운동 마치기",
                    onSkip: { model.stopRest() }, onFinish: { model.finishWorkout() }
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            if workspace == "일상", model.data.activeWorkout != nil {
                Button("진행 중인 운동으로 돌아가기") { workspace = "운동"; selectedTab = 0 }
                    .font(.subheadline).padding(.bottom, 8)
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
                SettingsView()
                    .tabItem { Label("설정", systemImage: "gearshape") }.tag(3)
            }
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
