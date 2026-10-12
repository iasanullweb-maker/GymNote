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

/// 위젯 버튼과 기존 단축어에서 지정된 시간으로 휴식 타이머를 시작한다.
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
        let next = data.nextUp(on: data.activeWorkout?.startedAt ?? Date())
        await RestController.start(seconds: seconds, title: next.title, info: next.info, sound: data.restSound, generation: snapshot.1)
        return .result()
    }
}

/// 기본 시간 없이 필수 시간을 요청하여 Siri의 후속 질문을 유도한다.
struct StartSpokenRestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "시간을 물어 휴식 시작"
    static var description: IntentDescription? = IntentDescription("휴식 시간을 물은 뒤 헬스노트 휴식 타이머를 시작해.")

    @Parameter(title: "휴식 시간",
               description: "예: 1분 30초 또는 90초.",
               defaultUnit: .seconds,
               supportsNegativeNumbers: false,
               requestValueDialog: "얼마 동안 쉴까요? 예를 들어 1분 30초라고 말해 주세요.")
    var duration: Measurement<UnitDuration>

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$duration) 동안 휴식 시작")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let seconds = Self.seconds(for: duration) else {
            throw $duration.needsValueError("휴식 시간을 5초 이상으로 말해 주세요.")
        }
        // 값이 해결된 뒤 기존 경로를 사용하므로 운동 상태와 계정 보호를 유지한다.
        _ = try await StartRestIntent(seconds: seconds).perform()
        return .result(dialog: "휴식 \(seconds)초를 시작했어요.")
    }

    static func seconds(for duration: Measurement<UnitDuration>) -> Int? {
        let value = duration.converted(to: .seconds).value
        guard value.isFinite, value >= 5, value < Double(Int.max) else { return nil }
        // 소수 초는 올림하여 요청한 휴식보다 짧아지지 않게 한다.
        return Int(value.rounded(.up))
    }
}
