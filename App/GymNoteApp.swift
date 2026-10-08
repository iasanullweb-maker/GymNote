import Combine
import SwiftUI
import UserNotifications

extension Notification.Name {
    /// 앱 화면 밖(알림 버튼 등)에서 저장소가 바뀌었음을 화면에 알린다.
    static let gymnoteStoreChanged = Notification.Name("gymnote.storeChanged")
    /// 알림을 눌러 다른 분야(일상)로 열어 달라는 요청. 편집 중이면 RootView가 무시한다.
    static let gymnoteOpenWorkspace = Notification.Name("gymnote.openWorkspace")
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
            // 편집 중인 화면을 덮어쓰지 않도록 바로 바꾸지 않고 RootView에 요청만 남긴다.
            UserDefaults.standard.set("일상", forKey: EditingNavigationGuard.pendingWorkspaceKey)
            NotificationCenter.default.post(name: .gymnoteOpenWorkspace, object: nil)
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
    @State private var editingNavigation = EditingNavigationGuard()
    @State private var tabScreenVersions = [0, 0, 0, 0]
    @State private var selectedDate = Date()
    @AppStorage("selectedWorkspace") private var workspace = "운동"

    var body: some View {
        GeometryReader { geometry in
            Group {
                if !account.initialized || account.connection == .checking {
                    ProgressView("기기 기록을 불러오는 중…")
                } else if account.showsWelcome {
                    AccountView(welcome: true)
                } else {
                    mainTabs(compact: geometry.size.width < 600)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.gymnoteCompactLayout, geometry.size.width < 600)
            .environment(\.editingNavigationGuard, editingNavigation)
        }
        .tint(.orange)
        .onChange(of: selectedTab) { previous, _ in
            // 떠난 탭의 상세 화면과 임시 화면 상태를 정리한다.
            // 운동 진행과 선택 날짜는 상위 모델/RootView에 보존된다.
            tabScreenVersions[previous] += 1
        }
        .onChange(of: workspace) { _, _ in
            for index in tabScreenVersions.indices {
                tabScreenVersions[index] += 1
            }
        }
        .onChange(of: model.selection.generation) { _, _ in
            // 계정이 바뀌면 탭 전체가 새로 만들어지므로 이전 편집기의 잠금을 남기지 않는다.
            editingNavigation.reset()
        }
        .onReceive(NotificationCenter.default.publisher(for: .gymnoteOpenWorkspace).receive(on: RunLoop.main)) { _ in
            applyPendingWorkspace()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                applyPendingWorkspace()
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
            applyPendingWorkspace()
            await RestController.requestPermissions()
        }
        .alert("저장소 확인", isPresented: Binding(get: { model.storageError != nil }, set: { if !$0 { model.storageError = nil } })) {
            Button("확인", role: .cancel) { model.storageError = nil }
        } message: { Text(model.storageError ?? "") }
    }

    private func mainTabs(compact: Bool) -> some View {
        VStack(spacing: 0) {
            WorkspaceSwitcher(selection: protectedSelection($workspace))
                .disabled(editingNavigation.isEditing)
                .padding(.horizontal, 16)
                .padding(.vertical, compact ? 4 : 10)
            if editingNavigation.isEditing {
                Text("편집 중에는 이동할 수 없어요. 저장하거나 취소한 뒤 이동해 주세요.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.bottom, 6)
            }
            if model.data.activeWorkout != nil || model.restEnd != nil {
                WorkoutStatusBanner(
                    startedAt: model.data.activeWorkout?.startedAt,
                    restStart: model.restStart, restEnd: model.restEnd,
                    finishTitle: model.workoutProgress.done == 0 ? "시작 취소" : "운동 마치기",
                    onSkip: { model.stopRest() }, onFinish: { model.finishWorkout() }
                )
                .disabled(editingNavigation.isEditing)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, compact ? 6 : 12)
            }
            if workspace == "일상", model.data.activeWorkout != nil {
                Button("진행 중인 운동으로 돌아가기") { workspace = "운동"; selectedTab = 0 }
                    .disabled(editingNavigation.isEditing)
                    .font(.subheadline).padding(.bottom, 8)
            }
            TabView(selection: protectedSelection($selectedTab)) {
                Group {
                    if workspace == "일상" { DailyTodayView() }
                    else { TodayView() }
                }
                .id("today-\(tabScreenVersions[0])")
                .tabItem { Label("실행", systemImage: "checkmark.circle") }.tag(0)
                Group {
                    if workspace == "일상" { DailyPlansView(selectedDate: $selectedDate) }
                    else { RoutineView(selectedDate: $selectedDate) }
                }
                .id("plans-\(tabScreenVersions[1])")
                .tabItem { Label("계획", systemImage: "calendar") }.tag(1)
                Group {
                    if workspace == "일상" { DailyHistoryView() }
                    else { RecordsView() }
                }
                .id("records-\(tabScreenVersions[2])")
                .tabItem { Label("기록", systemImage: "chart.bar") }.tag(2)
                SettingsView()
                    .id("settings-\(tabScreenVersions[3])")
                    .tabItem { Label("설정", systemImage: "gearshape") }.tag(3)
            }
            .toolbar(editingNavigation.isEditing ? .hidden : .automatic, for: .tabBar)
        }
        .id(model.selection.generation)
        // 로그인/불러오기 화면으로 바뀌어 탭이 사라지면 남은 편집 잠금을 정리한다.
        .onDisappear { editingNavigation.reset() }
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

    private func applyPendingWorkspace() {
        let defaults = UserDefaults.standard
        let pending = defaults.string(forKey: EditingNavigationGuard.pendingWorkspaceKey)
        guard pending != nil else { return }
        defaults.removeObject(forKey: EditingNavigationGuard.pendingWorkspaceKey)
        if let next = editingNavigation.resolvePendingWorkspace(pending, current: workspace) {
            workspace = next
        }
    }

    private func protectedSelection<Value: Equatable>(_ selection: Binding<Value>) -> Binding<Value> {
        Binding(get: { selection.wrappedValue }, set: { next in
            guard editingNavigation.allowsSelection(from: selection.wrappedValue, to: next) else { return }
            selection.wrappedValue = next
        })
    }
}
