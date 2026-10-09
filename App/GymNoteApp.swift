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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab = 0
    @State private var editingNavigation = EditingNavigationGuard()
    @State private var tabScreenVersions = [0, 0, 0, 0, 0]
    @State private var selectedDate = Date()
    @State private var completedWorkout: WorkoutSession?
    @State private var completionPhase = 0
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
        .onChange(of: model.data.activeWorkout) { previous, current in
            if current != nil { completedWorkout = nil }
            else if let previous, let saved = model.data.workouts.first(where: { $0.id == previous.id }) {
                completionPhase = 0
                completedWorkout = saved
            }
        }
        .onChange(of: model.selection.generation) { _, _ in completedWorkout = nil }
        .task(id: completedWorkout?.id) {
            guard completedWorkout != nil else { return }
            do {
                try await Task.sleep(for: .milliseconds(250))
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { completionPhase = 1 }
                try await Task.sleep(for: .milliseconds(900))
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { completionPhase = 2 }
                try await Task.sleep(for: .seconds(2))
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { completedWorkout = nil }
            } catch { /* A new session/account cancels the previous completion animation. */ }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
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
        .task {
            await account.bootstrap()
            model.reload()
            await RestController.requestPermissions()
            await model.social.refresh(quiet: true)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await account.refreshRecordCatalog()
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
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

    @ViewBuilder
    private func workoutStatus(compact: Bool) -> some View {
        if let completedWorkout {
            VStack(spacing: 8) {
                Image(systemName: completionPhase == 0 ? "figure.strengthtraining.traditional"
                      : completionPhase == 1 ? "checkmark.circle.fill" : "book.closed.fill")
                    .font(.title2).foregroundStyle(completionPhase == 0 ? .orange : .green)
                Text(completionPhase == 0 ? "운동 중" : completionPhase == 1 ? "운동 완료" : "운동 일지에 저장됨")
                    .font(.headline).contentTransition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
                Text("\(completedWorkout.done) / \(completedWorkout.total) 세트")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 16).padding(.vertical, 6)
            .accessibilityElement(children: .combine)
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
        }
    }

    private func protectedSelection<Value: Equatable>(_ selection: Binding<Value>) -> Binding<Value> {
        Binding(get: { selection.wrappedValue }, set: { next in
            guard editingNavigation.allowsSelection(from: selection.wrappedValue, to: next) else { return }
            selection.wrappedValue = next
        })
    }
}
