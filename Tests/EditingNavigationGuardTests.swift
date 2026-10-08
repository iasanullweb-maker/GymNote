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
}
