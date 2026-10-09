import Foundation
@testable import GymNote

/// Synthetic demo-v1 values only. Never load AppData.sample or a stored account.
enum UXSimulationFixtures {
    static let fixtureID = "demo-v1"
    static let anchorISO8601 = "2026-10-12T09:00:00+09:00"
    static let anchor = ISO8601DateFormatter().date(from: anchorISO8601)!
    static let timezone = TimeZone(identifier: "Asia/Seoul")!
    static let locale = Locale(identifier: "ko_KR")
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timezone
        value.locale = locale
        return value
    }
    static func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index))!
    }
    static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    enum Screen: String, CaseIterable {
        case workoutReady = "workout-ready", workoutActive = "workout-active", workoutRest = "workout-rest"
        case planMonth = "plan-month", planDateDetail = "plan-date-detail", recordsOverview = "records-overview"
        case journalCalendar = "journal-calendar", journalEntry = "journal-entry"
        case friendsHome = "friends-home", friendsRanking = "friends-ranking"

        var blockedReason: String? {
            switch self {
            case .workoutRest:
                return "WorkoutStatusBanner reads TimelineView context.date and Text(timer). No clock injection exists; fixed rest dates cannot reliably render a resting state."
            case .journalCalendar:
                return "WorkoutJournalView privately initializes selectedDate with Date(). No fixed-date initializer exists; do not substitute a calendar component for the full journal screen."
            case .friendsHome, .friendsRanking:
                return "FriendsView / FriendRankingView require private authenticated SocialModel overview and ranking state. No offline fixture injection exists; a guest gate is not a populated management/ranking capture."
            default: return nil
            }
        }
    }
    static func makeData(for screen: Screen = .workoutReady) -> AppData {
        let push = Exercise(id: id(1), name: "푸쉬업", sets: 3, detail: "10회")
        let pull = Exercise(id: id(2), name: "풀업", sets: 3, detail: "5회")
        let stretch = Exercise(id: id(3), name: "어깨와 등 스트레칭", sets: 2, detail: "1분")
        let plan = DayPlan(title: "상체와 스트레칭", exercises: [push, pull, stretch])
        // AppData.init creates a current-week schedule/library internally. Replace BOTH
        // before returning; those transient Date()/UUID() values never enter the fixture.
        var data = AppData(week: Array(repeating: plan, count: 7), recordTypes: CatalogRecordType.defaults.map(\.recordType))
        data.scheduledPlans = [:]
        for offset in 0..<31 {
            let day = calendar.date(byAdding: .day, value: offset, to: date("2026-10-01T09:00:00+09:00"))!
            let components = calendar.dateComponents([.year, .month, .day], from: day)
            let key = String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
            data.scheduledPlans[key] = offset % 3 == 2 ? DayPlan(title: "휴식", exercises: []) : plan
        }
        data.scheduledPlans["2026-10-12"] = plan
        data.exerciseLibrary = [push, pull, stretch]
        data.dailyReminders.enabled = false
        var first = RecordEntry(typeID: "common-pushup-v1", date: date("2026-10-01T09:00:00+09:00"), value: 15)
        first.id = id(10)
        var second = RecordEntry(typeID: "common-pushup-v1", date: date("2026-10-08T09:00:00+09:00"), value: 18)
        second.id = id(11)
        var third = RecordEntry(typeID: "common-pullup-v1", date: second.date, value: 8)
        third.id = id(12)
        data.records = [first, second, third]
        data.workouts = [WorkoutSession(id: id(20), startedAt: date("2026-10-08T08:00:00+09:00"),
            endedAt: date("2026-10-08T08:25:00+09:00"), plan: plan,
            completedSets: [push.id.uuidString: 3, pull.id.uuidString: 3],
            actualReps: [push.id.uuidString: [10, 12, 11], pull.id.uuidString: [5, 5, 4]])]
        if screen == .workoutActive || screen == .workoutRest {
            data.activeWorkout = WorkoutSession(id: id(21), startedAt: anchor.addingTimeInterval(-600), plan: plan,
                completedSets: [push.id.uuidString: 1], actualReps: [push.id.uuidString: [10]])
        }
        return data
    }
    static func makeDraft() -> ManualWorkoutDraft {
        // A fixed prior day, valid even before the anchor day. App still checks Date().
        ManualWorkoutDraft(date: date("2026-10-08T09:00:00+09:00"), title: "아침 상체 운동",
            moves: [ManualWorkoutDraft.Move(id: id(30), name: "푸쉬업", detail: "10회", sets: [
                ManualWorkoutDraft.SetEntry(id: id(31), reps: "10", weight: ""),
                ManualWorkoutDraft.SetEntry(id: id(32), reps: "12", weight: "")])])
    }
    @MainActor static func makeModel(for screen: Screen) -> AppModel {
        let model = AppModel(previewData: makeData(for: screen))
        if screen == .workoutRest {
            model.restStart = anchor.addingTimeInterval(-30)
            model.restEnd = anchor.addingTimeInterval(60)
        }
        return model
    }
}
