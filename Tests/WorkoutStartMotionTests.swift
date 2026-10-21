import SwiftUI
import XCTest
@testable import GymNote

/// 운동 시작 애니메이션(B 변신 / A 올라오기)의 상태 흐름. 실제 움직임은 실기기에서 확인한다.
@MainActor
final class WorkoutStartMotionTests: XCTestCase {
    func testDefaultStyleIsMorphAndBothStylesHaveTitles() {
        XCTAssertEqual(WorkoutStartAnimationStyle.defaultStyle, .morph)
        XCTAssertEqual(WorkoutStartAnimationStyle(rawValue: "rise"), .rise)
        XCTAssertEqual(Set(WorkoutStartAnimationStyle.allCases.map(\.title)).count, 2)
    }

    func testMorphNeedsStartButtonFrame() {
        let motion = WorkoutStartMotion()
        XCTAssertFalse(motion.beginMorph(), "버튼 위치를 모르면 A처럼 처리하도록 false")
        XCTAssertEqual(motion.phase, .idle)
        XCTAssertFalse(motion.barHidden)
    }

    func testMorphFliesFromButtonToBarThenRevealsBarAndPulses() {
        let motion = WorkoutStartMotion()
        let button = CGRect(x: 20, y: 200, width: 400, height: 52)
        let bar = CGRect(x: 16, y: 1000, width: 720, height: 96)
        motion.startFrame = button
        XCTAssertTrue(motion.beginMorph())
        XCTAssertEqual(motion.phase, .waitingForBar)
        XCTAssertTrue(motion.barHidden, "날아가는 동안 진짜 바는 숨김")
        XCTAssertEqual(motion.from, button)
        XCTAssertEqual(motion.to, button, "바 위치를 받기 전에는 버튼 자리에 그대로")

        motion.barFrameChanged(.zero)
        XCTAssertEqual(motion.phase, .waitingForBar, "크기 없는 frame은 무시")
        motion.barFrameChanged(bar)
        XCTAssertEqual(motion.phase, .flying)
        XCTAssertEqual(motion.to, bar)

        motion.land()
        XCTAssertEqual(motion.phase, .idle)
        XCTAssertFalse(motion.barHidden)
        XCTAssertEqual(motion.pulse, 1)
        motion.land()
        XCTAssertEqual(motion.pulse, 1, "이미 착지했으면 다시 반짝이지 않음")
    }

    func testBarFrameOutsideMorphIsIgnoredAndResetClears() {
        let motion = WorkoutStartMotion()
        motion.barFrameChanged(CGRect(x: 0, y: 0, width: 100, height: 50))
        XCTAssertEqual(motion.phase, .idle)
        motion.startFrame = CGRect(x: 0, y: 0, width: 100, height: 52)
        motion.beginMorph()
        motion.reset()
        XCTAssertEqual(motion.phase, .idle)
        XCTAssertEqual(motion.pulse, 0, "취소는 반짝이지 않음")
        motion.risen()
        XCTAssertEqual(motion.pulse, 1)
    }

    func testMorphFallsBackWhenBarNeverReportsFrame() async throws {
        let motion = WorkoutStartMotion()
        motion.startFrame = CGRect(x: 0, y: 0, width: 100, height: 52)
        motion.beginMorph()
        try await Task.sleep(for: .milliseconds(1100))
        XCTAssertEqual(motion.phase, .idle, "바 위치가 끝내 오지 않으면 판을 거두고 바를 보인다")
        XCTAssertEqual(motion.pulse, 1)
    }
}
