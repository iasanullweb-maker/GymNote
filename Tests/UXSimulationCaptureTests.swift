import SwiftUI
import UIKit
import XCTest
@testable import GymNote

#if DEBUG
@MainActor
final class UXSimulationCaptureTests: XCTestCase {
    typealias Screen = UXSimulationFixtures.Screen

    /// AccountModel.init reads the catalog under a lock even with client:nil.
    /// Redirect that access before constructing ANY account, and restore the global hook.
    private func isolated(_ action: (URL) async throws -> Void) async throws {
        let previousDirectory = SharedStore.testingDirectory
        let previousTimezone = NSTimeZone.default
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gymnote-ux-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        SharedStore.testingDirectory = directory
        NSTimeZone.default = UXSimulationFixtures.timezone
        defer {
            SharedStore.testingDirectory = previousDirectory
            NSTimeZone.default = previousTimezone
            try? FileManager.default.removeItem(at: directory)
        }
        try await action(directory)
    }

    private func capture(_ screen: Screen, width: Int = 834, height: Int = 1194,
                         accessibility: Bool = false) async throws {
        if let reason = screen.blockedReason { throw XCTSkip(reason) }
        if screen == .workoutReady, !UXSimulationFixtures.calendar.isDate(Date(), inSameDayAs: UXSimulationFixtures.anchor) {
            throw XCTSkip("TodayView uses AppModel.todayPlan/workoutDate Date() when idle. Run this entry point on the anchor day; no fixed-clock injection exists.")
        }
        try await isolated { _ in
            let model = UXSimulationFixtures.makeModel(for: screen)
            let account = AccountModel(model: model, client: nil, initialConnection: .offline, monitorConnectivity: false)
            // Prevent lazy construction of a configured, monitored account by nested views.
            model.account = account
            let suiteName = "com.gymnote.ux-capture." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set(String(decoding: try JSONEncoder().encode(UXSimulationFixtures.makeDraft()), as: UTF8.self),
                         forKey: ManualWorkoutDraft.storageKey(userID: UXSimulationFixtures.id(90)))
            let root = entryPoint(screen, model: model)
                .environment(model).environment(account)
                .environment(\.locale, UXSimulationFixtures.locale)
                .environment(\.calendar, UXSimulationFixtures.calendar)
                .environment(\.timeZone, UXSimulationFixtures.timezone)
                .environment(\.gymnoteCompactLayout, width < 600)
                .environment(\.dynamicTypeSize, accessibility ? .accessibility3 : .large)
                .defaultAppStorage(defaults).preferredColorScheme(.light).tint(.orange)
                .frame(width: CGFloat(width), height: CGFloat(height))
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
            window.rootViewController = UIHostingController(rootView: root)
            defer {
                window.isHidden = true
                window.rootViewController = nil
                previousKeyWindow?.makeKey()
            }
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 700_000_000)
            XCTAssertEqual(window.bounds.width, CGFloat(width))
            XCTAssertEqual(window.bounds.height, CGFloat(height))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1 // PNG pixels equal manifest pt bounds, independent of simulator scale.
            var rendered = false
            let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            guard rendered else { XCTFail("drawHierarchy failed; no PNG attachment emitted"); return }
            let pixels = try XCTUnwrap(image.cgImage?.dataProvider?.data)
            let bytes = try XCTUnwrap(CFDataGetBytePtr(pixels))
            let length = CFDataGetLength(pixels)
            guard stride(from: 4, to: length, by: 4).contains(where: { bytes[$0] != bytes[0] }) else {
                XCTFail("Empty/solid render; no PNG attachment emitted"); return
            }
            let png = try XCTUnwrap(image.pngData())
            let name = "\(screen.rawValue)--\(width)x\(height)--\(accessibility ? "accessibility" : "standard")"
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = name + ".png"
            attachment.lifetime = .keepAlways
            add(attachment)
            let metadata: [String: String] = ["captureId": screen.rawValue, "fixtureId": "demo-v1",
                "anchorTime": UXSimulationFixtures.anchorISO8601,
                "renderedAt": ISO8601DateFormatter().string(from: Date()),
                "clock": "system-clock-not-frozen", "scope": "direct-product-view-without-root-tab-chrome"]
            let receipt = XCTAttachment(data: try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]),
                                        uniformTypeIdentifier: "public.json")
            receipt.name = name + ".metadata.json"
            receipt.lifetime = .keepAlways
            add(receipt)
            XCTAssertNil(account.user)
            XCTAssertFalse(account.configured)
        }
    }

    @ViewBuilder
    private func entryPoint(_ screen: Screen, model: AppModel) -> some View {
        switch screen {
        case .workoutReady, .workoutActive: TodayView()
        case .planMonth: RoutineView(selectedDate: .constant(UXSimulationFixtures.anchor))
        case .planDateDetail: NavigationStack { ScheduledDayEditor(date: UXSimulationFixtures.anchor) }
        case .recordsOverview: RecordsView()
        case .journalEntry:
            ManualWorkoutView(date: UXSimulationFixtures.makeDraft().date, userID: UXSimulationFixtures.id(90), onSave: { _ in })
        case .workoutRest, .journalCalendar, .friendsHome, .friendsRanking:
            // capture() skips BEFORE entering this branch; no placeholder screenshot.
            EmptyView()
        }
    }

    func testWorkoutReady() async throws { try await capture(.workoutReady) }
    func testWorkoutActive() async throws { try await capture(.workoutActive) }
    func testWorkoutRest() async throws { try await capture(.workoutRest) }
    func testPlanMonth() async throws { try await capture(.planMonth) }
    func testPlanDateDetail() async throws { try await capture(.planDateDetail) }
    func testRecordsOverview() async throws { try await capture(.recordsOverview) }
    func testJournalCalendar() async throws { try await capture(.journalCalendar) }
    func testJournalEntry() async throws { try await capture(.journalEntry) }
    func testFriendsHome() async throws { try await capture(.friendsHome) }
    func testFriendsRanking() async throws { try await capture(.friendsRanking) }

    func testPlanDetailAccessibility() async throws {
        try await capture(.planDateDetail, accessibility: true)
    }
    func testWorkoutSplitView() async throws {
        try await capture(.workoutActive, width: 417, height: 1194)
    }

    func testFixtureIsStableAndCopiesAreIndependent() async throws {
        try await isolated { _ in
            let first = UXSimulationFixtures.makeData(for: .workoutActive)
            var second = UXSimulationFixtures.makeData(for: .workoutActive)
            XCTAssertEqual(first, second)
            XCTAssertEqual(first.scheduledPlans.count, 31)
            XCTAssertEqual(first.scheduledPlans["2026-10-12"]?.totalSets, 8)
            XCTAssertEqual(first.activeWorkout?.id, UXSimulationFixtures.id(21))
            XCTAssertEqual(first.activeWorkout?.startedAt, UXSimulationFixtures.anchor.addingTimeInterval(-600))
            XCTAssertEqual(first.workouts.first?.actualReps[UXSimulationFixtures.id(1).uuidString], [10, 12, 11])
            second.records.removeAll()
            second.week[0].exercises[0].name = "changed only in copy"
            XCTAssertEqual(first.records.count, 3)
            XCTAssertEqual(first.week[0].exercises[0].name, "푸쉬업")
            XCTAssertEqual(UXSimulationFixtures.makeDraft(), UXSimulationFixtures.makeDraft())
        }
    }

    func testPreviewMutationAndOfflineRefreshDoNotPersistOrAuthenticate() async throws {
        try await isolated { directory in
            let model = UXSimulationFixtures.makeModel(for: .workoutActive)
            let account = AccountModel(model: model, client: nil, initialConnection: .offline, monitorConnectivity: false)
            model.account = account
            let before = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            model.data.records.removeAll()
            model.data.dailyItems.removeAll()
            model.undoSet(model.data.activeWorkout!.plan.exercises[0])
            await account.refreshRecordCatalog()
            await account.refreshProviders()
            await model.social.refresh()
            await model.social.publish(force: true)
            let after = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            XCTAssertEqual(before.sorted(), after.sorted())
            XCTAssertFalse(after.contains { $0.hasSuffix(".json") })
            XCTAssertNil(model.storageError)
            XCTAssertNil(model.selection.userID)
            XCTAssertNil(account.session)
            XCTAssertFalse(account.configured)
            XCTAssertFalse(account.isOnline)
            XCTAssertNil(model.social.overview)
            // No bootstrap/login/switchAccount/reload/SharedStore.snapshot calls here.
        }
    }
}
#endif
