import Accessibility
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
    @State private var model: AppModel

    init() {
        // Must run before AppModel creates the store files: it tells a fresh install from an update.
        DailyReminderScheduler.prepareDevicePreference()
        _model = State(initialValue: AppModel())
    }

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab = 0
    @State private var editingNavigation = EditingNavigationGuard()
    @State private var tabScreenVersions = [0, 0, 0, 0, 0]
    @State private var selectedDate = Date()
    /// 종료 애니메이션 단계. 운동 ID별로 두어 새 저장이 오면 항상 '운동 중'부터 시작한다.
    @State private var completion: (id: UUID, phase: Int)?
    @State private var lastCatalogRefresh: Date?
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
            .environment(\.openFriendsTab, { selectedTab = 3 })
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
        .onChange(of: model.data.activeWorkout?.id) { _, current in
            // 빠르게 새 운동을 시작하면 이전 종료 표시를 바로 거둔다.
            if current != nil { model.dismissSavedWorkout() }
        }
        .onChange(of: model.selection.generation) { _, _ in model.dismissSavedWorkout() }
        // AppModel.savedWorkout은 일지 저장이 실제로 성공했을 때만 생긴다.
        // 단계: 운동 중 → 운동 완료 → 운동 일지에 저장됨 → 사라짐. 새 운동·계정 전환이면 취소된다.
        .task(id: model.savedWorkout?.id) {
            guard let id = model.savedWorkout?.id else { completion = nil; return }
            completion = (id, 0)
            let animation: Animation? = reduceMotion ? nil : .easeInOut(duration: 0.3)
            do {
                try await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 350))
                withAnimation(animation) { completion = (id, 1) }
                try await Task.sleep(for: .milliseconds(900))
                withAnimation(animation) { completion = (id, 2) }
                AccessibilityNotification.Announcement("운동 일지에 저장됨").post()
                try await Task.sleep(for: .seconds(2))
                withAnimation(animation) { model.dismissSavedWorkout(id) }
            } catch { /* A new session/account cancels the previous completion animation. */ }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refreshCurrentDate()
                model.reload()
                account.scheduleSync()
                Task { await model.social.publish(force: false) }
                Task { await model.social.refresh(quiet: true) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .gymnoteStoreChanged).receive(on: RunLoop.main)) { _ in
            model.reload()
            account.scheduleSync()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            model.refreshCurrentDate()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification).receive(on: RunLoop.main)) { _ in
            model.refreshCurrentDate()
        }
        .task {
            await account.bootstrap()
            model.reload()
            await RestController.requestPermissions()
            await model.social.refresh(quiet: true)
        }
        .task(id: scenePhase) {
            // 앱이 화면에 있는 동안만 60초마다 공통 종목을 갱신한다. 백그라운드·비활성으로 바뀌면 반복을 멈춘다.
            // 진행 중인 요청은 끊지 않고 끝까지 받는다(취소 오류를 '갱신 실패'로 보이지 않게).
            // 동시에 들어온 요청은 AccountModel.catalogLoading이 걸러 낸다.
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                // 잠깐 비활성(제어 센터·알림 등)됐다 돌아올 때 곧바로 다시 요청하지 않는다.
                if lastCatalogRefresh.map({ Date().timeIntervalSince($0) >= 30 }) ?? true {
                    lastCatalogRefresh = Date()
                    let refresh = Task { await account.refreshRecordCatalog() }
                    await refresh.value
                }
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
            }
        }
        .task(id: scenePhase) {
            // 앱이 화면에 있는 동안 30초마다 서버 버전만 확인하고, 다른 기기가 저장했으면 동기화한다.
            // 앱을 닫으면 iOS가 주기 실행을 보장하지 않으므로 다음에 열 때 맞춘다.
            // 편집 화면이 열려 있는 동안은 화면 내용이 바뀌지 않도록 건너뛴다.
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return }
                if !editingNavigation.isEditing { await account.checkForRemoteChanges() }
            }
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
                .safeAreaInset(edge: .bottom, spacing: 0) { workoutStatus(compact: compact) }
                .id("today-\(tabScreenVersions[0])")
                .tabItem { Label("실행", systemImage: "checkmark.circle") }.tag(0)
                Group {
                    if workspace == "일상" { DailyPlansView(selectedDate: $selectedDate) }
                    else { RoutineView(selectedDate: $selectedDate) }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { workoutStatus(compact: compact) }
                .id("plans-\(tabScreenVersions[1])")
                .tabItem { Label("계획", systemImage: "calendar") }.tag(1)
                Group {
                    if workspace == "일상" { DailyHistoryView() }
                    else { RecordsView() }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { workoutStatus(compact: compact) }
                .id("records-\(tabScreenVersions[2])")
                .tabItem { Label("기록", systemImage: "chart.bar") }.tag(2)
                FriendsView()
                    .safeAreaInset(edge: .bottom, spacing: 0) { workoutStatus(compact: compact) }
                    .id("friends-\(tabScreenVersions[3])")
                    .tabItem { Label("친구", systemImage: "person.2") }
                    .badge(model.social.pendingCount)
                    .tag(3)
                SettingsView()
                    .safeAreaInset(edge: .bottom, spacing: 0) { workoutStatus(compact: compact) }
                    .id("settings-\(tabScreenVersions[4])")
                    .tabItem { Label("설정", systemImage: "gearshape") }.tag(4)
            }
            .toolbar(editingNavigation.isEditing ? .hidden : .automatic, for: .tabBar)
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

    /// 각 탭 콘텐츠의 하단 safeAreaInset에 놓여 탭 막대 위에 붙는다. 목록은 이 높이만큼 아래 여백을 받아
    /// 마지막 버튼까지 스크롤해 누를 수 있다. 큰 글자에서도 화면을 덮지 않도록 글자 크기 상한을 둔다.
    @ViewBuilder
    private func workoutStatus(compact: Bool) -> some View {
        if let saved = model.savedWorkout {
            WorkoutCompletionBanner(session: saved,
                                    phase: completion?.id == saved.id ? completion?.phase ?? 0 : 0)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16).padding(.vertical, compact ? 6 : 10)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .transition(.opacity)
        } else if model.data.activeWorkout != nil || model.restEnd != nil {
            WorkoutStatusBanner(
                startedAt: model.data.activeWorkout?.startedAt,
                restStart: model.restStart, restEnd: model.restEnd,
                finishTitle: model.workoutProgress.done == 0 ? "시작 취소" : "운동 마치기",
                onSkip: { model.stopRest() }, onFinish: { model.finishWorkout() },
                doneSets: model.workoutProgress.done, totalSets: model.workoutProgress.total
            )
            .disabled(editingNavigation.isEditing)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16).padding(.vertical, compact ? 6 : 10)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
    }

    private func protectedSelection<Value: Equatable>(_ selection: Binding<Value>) -> Binding<Value> {
        Binding(get: { selection.wrappedValue }, set: { next in
            guard editingNavigation.allowsSelection(from: selection.wrappedValue, to: next) else { return }
            selection.wrappedValue = next
        })
    }
}
