import AppIntents
import Foundation

/// 위젯에서 운동을 탭하면 세트 +1 (다 채운 상태에서 탭하면 0으로 되돌림)
struct CompleteSetIntent: AppIntent {
    static var title: LocalizedStringResource = "세트 체크"
    static var isDiscoverable: Bool = false

    @Parameter(title: "운동 ID")
    var exerciseID: String

    init() {}

    init(exerciseID: String) {
        self.exerciseID = exerciseID
    }

    func perform() async throws -> some IntentResult {
        var data = SharedStore.load()
        if let id = UUID(uuidString: exerciseID) {
            data.changeSets(id, by: 1, wrap: true)
            SharedStore.save(data)
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

    init() {}

    init(seconds: Int) {
        self.seconds = seconds
    }

    func perform() async throws -> some IntentResult {
        let next = SharedStore.load().nextUp()
        await RestController.start(seconds: seconds, title: next.title, info: next.info)
        return .result()
    }
}
