import SwiftUI
import UIKit
import XCTest
@testable import GymNote

@MainActor
final class DisplayTests: XCTestCase {
    private func fixture() -> AppData {
        var data = AppData.sample
        let moves = (1...8).map { Exercise(name: "긴 이름 운동 \($0) · 스쿼트와 스트레칭", sets: 3, detail: "10회") }
        for (index, date) in DayKey.monthDates(containing: Date()).enumerated() {
            data.scheduledPlans[DayKey.key(date)] = DayPlan(title: "검증 계획", exercises: index % 2 == 0 ? moves : Array(moves.prefix(1)))
            data.dailyItems += (1...(index % 2 == 0 ? 8 : 1)).map {
                DailyItem(title: "긴 이름 일상 \($0) · 독서와 스트레칭", scheduledDate: date, startDate: date)
            }
        }
        let day = Calendar.current.startOfDay(for: Date())
        data.workouts = [
            WorkoutSession(startedAt: day.addingTimeInterval(3600), plan: DayPlan(title: "아침 운동", exercises: Array(moves.prefix(2))), completedSets: [moves[0].id.uuidString: 2]),
            WorkoutSession(startedAt: day.addingTimeInterval(7200), plan: DayPlan(title: "저녁 운동", exercises: Array(moves.prefix(3))), completedSets: [moves[1].id.uuidString: 3])
        ]
        return data
    }

    private func host<V: View>(_ view: V, name: String) async throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 834, height: 1194)
        window.rootViewController = UIHostingController(rootView: view.tint(.orange))
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 500_000_000)
        capture(window, name: name)
        return window
    }

    private func capture(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true), "화면 캡처 렌더링 성공")
        }
        if let data = image.cgImage?.dataProvider?.data, let pixels = CFDataGetBytePtr(data) {
            let count = CFDataGetLength(data)
            XCTAssertTrue(stride(from: 4, to: count, by: 4).contains { pixels[$0] != pixels[0] }, "빈 화면 캡처를 성공으로 처리하지 않음")
        } else { XCTFail("화면 캡처 픽셀 없음") }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func scrollingView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height {
            return scroll
        }
        return view.subviews.compactMap { scrollingView(in: $0) }.first
    }

    func testTallPlanCalendarScrollSettlesWithoutHeightChanges() async throws {
        let model = AppModel(previewData: fixture())
        let window = try await host(RoutineView(selectedDate: .constant(Date())).environment(model), name: "plan-top")
        defer { window.isHidden = true }
        try await checkScroll(window)
        capture(window, name: "plan-scrolled")
    }

    func testDailyPlanCalendarScrollSettlesWithoutHeightChanges() async throws {
        let model = AppModel(previewData: fixture())
        let window = try await host(DailyPlansView(selectedDate: .constant(Date())).environment(model), name: "daily-plan-top")
        defer { window.isHidden = true }
        try await checkScroll(window)
        capture(window, name: "daily-plan-scrolled")
    }

    private func checkScroll(_ window: UIWindow) async throws {
        let scroll = try XCTUnwrap(scrollingView(in: window))
        let initialHeight = scroll.contentSize.height
        let maximum = max(0, initialHeight - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        for fraction in [0.25, 0.5, 0.75, 0.5, 0.25] {
            scroll.setContentOffset(CGPoint(x: 0, y: maximum * fraction), animated: true)
            try await Task.sleep(nanoseconds: 700_000_000)
            let offset = scroll.contentOffset.y
            let height = scroll.contentSize.height
            try await Task.sleep(nanoseconds: 300_000_000)
            XCTAssertEqual(scroll.contentOffset.y, offset, accuracy: 1, "스크롤 정지 후 위치가 튀지 않아야 함")
            XCTAssertEqual(scroll.contentSize.height, height, accuracy: 1)
            XCTAssertEqual(height, initialHeight, accuracy: 2, "캘린더를 스크롤해도 전체 높이가 바뀌지 않아야 함")
        }
    }

    func testJournalAndRecordScreensRender() async throws {
        let model = AppModel(previewData: fixture())
        let journal = try await host(NavigationStack { WorkoutJournalView() }.environment(model), name: "journal-calendar")
        journal.isHidden = true
        let records = try await host(RecordsView().environment(model).environment(model.account), name: "record-buttons")
        records.isHidden = true
        let rest = try await host(WorkoutStatusBanner(startedAt: Date(), restStart: Date(), restEnd: Date().addingTimeInterval(90), finishTitle: "운동 마치기", onSkip: {}, onFinish: {}).padding(), name: "rest-minutes-seconds")
        rest.isHidden = true
    }
}
