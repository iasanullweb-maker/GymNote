import AppIntents

/// 단축어 앱과 Siri에 "휴식 타이머 시작"을 등록
struct GymNoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRestIntent(),
            phrases: ["\(.applicationName) 휴식 시작"],
            shortTitle: "휴식 타이머",
            systemImageName: "timer"
        )
    }
}
