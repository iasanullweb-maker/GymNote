import AppIntents
import Foundation

/// 위젯에서 운동을 탭하면 세트 +1 (다 채운 상태에서 탭하면 0으로 되돌림)
struct CompleteSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "세트 체크"
    static var isDiscoverable: Bool = false

    @Parameter(title: "운동 ID")
    var exerciseID: String

    @Parameter(title: "계정 전환 확인")
    var generation: String

    init() {}

    init(exerciseID: String, generation: String) {
        self.exerciseID = exerciseID
        self.generation = generation
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: exerciseID) {
            let before = SharedStore.widgetSnapshot()
            try SharedStore.completeSet(id, generation: generation)
            let snapshot = SharedStore.widgetSnapshot()
            guard snapshot.1 == generation else { return .result() }
            let session = snapshot.0.activeWorkout
            let finished = before.0.activeWorkout != nil && session == nil
            let currentRest = await RestController.current()
            let rest = finished ? nil : currentRest
            let next = snapshot.0.nextUp()
            await RestController.update(workoutStartedAt: session?.startedAt,
                                        restStart: rest?.start, restEnd: rest?.end,
                                        title: next.title, info: next.info, generation: generation)
        }
        return .result()
    }
}

/// 휴식 타이머 시작 (위젯 버튼, 단축어, Siri에서 사용)
struct StartRestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "휴식 타이머 시작"
    static var description: IntentDescription? = IntentDescription("헬스노트 휴식 타이머를 시작하고 잠금 화면에 표시해.")

    @Parameter(title: "휴식 시간(초)", default: 90)
    var seconds: Int

    @Parameter(title: "계정 전환 확인", default: "")
    var generation: String

    init() {}

    init(seconds: Int, generation: String = "") {
        self.seconds = seconds
        self.generation = generation
    }

    func perform() async throws -> some IntentResult {
        let snapshot = SharedStore.widgetSnapshot()
        guard generation.isEmpty || generation == snapshot.1 else { return .result() }
        let data = snapshot.0
        let next = data.nextUp()
        await RestController.start(seconds: seconds, title: next.title, info: next.info, sound: data.restSound, generation: snapshot.1)
        return .result()
    }
}
