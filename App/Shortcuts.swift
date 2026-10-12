import AppIntents

/// Siri가 휴식 시간을 물은 뒤 타이머를 시작한다.
struct GymNoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSpokenRestIntent(),
            phrases: ["\(.applicationName) 휴식 시작"],
            shortTitle: "휴식 타이머",
            systemImageName: "timer"
        )
    }
}
