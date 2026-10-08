import ActivityKit
import XCTest
@testable import GymNote

final class WorkoutActivityTests: XCTestCase {
    func testWorkoutRestAndExpiryPresentation() throws {
        let start = Date(timeIntervalSince1970: 1000)
        let restStart = start.addingTimeInterval(60)
        let end = restStart.addingTimeInterval(90)
        let working = RestAttributes.ContentState(endDate: start, title: "스쿼트", info: "1/3세트",
                                                  workoutStartedAt: start)
        XCTAssertFalse(working.isResting(at: restStart))
        let resting = RestAttributes.ContentState(endDate: end, title: "스쿼트", info: "2/3세트",
                                                  workoutStartedAt: start, restStartedAt: restStart)
        XCTAssertTrue(resting.isResting(at: restStart))
        XCTAssertFalse(resting.isResting(at: end), "휴식 종료 후 운동 경과 시간 표시로 복귀")
        XCTAssertFalse(resting.isResting(at: restStart, stale: true), "앱이 잠들어도 시스템 stale 상태로 복귀")
        let restored = try JSONDecoder().decode(RestAttributes.ContentState.self, from: JSONEncoder().encode(resting))
        XCTAssertEqual(restored.workoutStartedAt, start)
        XCTAssertEqual(restored.restStartedAt, restStart)
        let standalone = RestAttributes.ContentState(endDate: end, title: "휴식", info: "")
        XCTAssertTrue(standalone.isResting(at: restStart))
        XCTAssertFalse(standalone.isResting(at: end))
    }

    func testLegacyRestActivityDecodesWithoutWorkoutFields() throws {
        let data = Data("{\"endDate\":150,\"title\":\"휴식\",\"info\":\"\"}".utf8)
        let state = try JSONDecoder().decode(RestAttributes.ContentState.self, from: data)
        XCTAssertNil(state.workoutStartedAt)
        XCTAssertNil(state.restStartedAt)
        XCTAssertTrue(state.isResting(at: Date(timeIntervalSinceReferenceDate: 100)))
    }
}
