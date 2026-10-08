import XCTest
@testable import GymNote

final class EditingNavigationGuardTests: XCTestCase {
    func testSwitchingTabsAndWorkspacesRequiresFinishingEditing() {
        let navigation = EditingNavigationGuard()
        let editor = UUID()
        navigation.begin(editor)
        XCTAssertFalse(navigation.allowsSelection(from: 2, to: 1))
        XCTAssertFalse(navigation.allowsSelection(from: "운동", to: "일상"))
        XCTAssertTrue(navigation.allowsSelection(from: 2, to: 2))
        navigation.end(editor)
        XCTAssertTrue(navigation.allowsSelection(from: 2, to: 1))
        XCTAssertTrue(navigation.allowsSelection(from: "운동", to: "일상"))
    }

    func testNestedEditorsAndRepeatedAppearanceDoNotUnlockEarly() {
        let navigation = EditingNavigationGuard()
        let first = UUID(), second = UUID()
        navigation.begin(first)
        navigation.begin(first)
        navigation.begin(second)
        navigation.end(first)
        navigation.end(first)
        XCTAssertTrue(navigation.isEditing)
        navigation.end(second)
        XCTAssertFalse(navigation.isEditing)
    }

    func testSaveOrCancelReleasesLockForEveryDestination() {
        let navigation = EditingNavigationGuard()
        let editor = UUID()
        navigation.begin(editor)
        XCTAssertFalse(navigation.allowsSelection(from: 1, to: 0))
        // 저장·취소 모두 편집 창을 닫아 onDisappear → end로 끝난다.
        navigation.end(editor)
        for target in 0...3 {
            XCTAssertTrue(navigation.allowsSelection(from: 1, to: target))
        }
        // 이미 닫힌 편집기의 늦은 end 호출은 새 편집을 풀지 않는다.
        let next = UUID()
        navigation.begin(next)
        navigation.end(editor)
        XCTAssertTrue(navigation.isEditing)
        navigation.end(next)
    }

    func testResetClearsStaleLockAfterScreenReplacement() {
        let navigation = EditingNavigationGuard()
        navigation.begin(UUID())
        navigation.begin(UUID())
        navigation.reset()
        XCTAssertFalse(navigation.isEditing)
        XCTAssertTrue(navigation.allowsSelection(from: "운동", to: "일상"))
    }

    func testNotificationWorkspaceRequestDoesNotInterruptEditing() {
        let navigation = EditingNavigationGuard()
        XCTAssertEqual(navigation.resolvePendingWorkspace("일상", current: "운동"), "일상")
        XCTAssertNil(navigation.resolvePendingWorkspace(nil, current: "운동"))

        let editor = UUID()
        navigation.begin(editor)
        XCTAssertNil(navigation.resolvePendingWorkspace("일상", current: "운동"))
        XCTAssertEqual(navigation.resolvePendingWorkspace("일상", current: "일상"), "일상")
        navigation.end(editor)
        XCTAssertEqual(navigation.resolvePendingWorkspace("일상", current: "운동"), "일상")
    }
}
