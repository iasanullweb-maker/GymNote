import ActivityKit
import Foundation
import UserNotifications

/// 잠금 화면 휴식 타이머 (Live Activity)
struct RestAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var endDate: Date
        var title: String   // 다음 운동 이름
        var info: String    // 예: "3/5세트 · 10회"
    }

    var startDate: Date
}

enum RestController {
    static let notificationID = "gymnote.rest.end"

    /// 휴식 타이머 시작: 잠금 화면 카운트다운 + 끝날 때 알림
    static func start(seconds: Int, title: String, info: String) async {
        await stop()

        let seconds = max(seconds, 5)
        let start = Date()
        let end = start.addingTimeInterval(TimeInterval(seconds))

        if ActivityAuthorizationInfo().areActivitiesEnabled {
            let state = RestAttributes.ContentState(endDate: end, title: title, info: info)
            // staleDate가 지나면 잠금 화면에 "휴식 끝!"으로 바뀜
            let content = ActivityContent(state: state, staleDate: end)
            _ = try? Activity<RestAttributes>.request(
                attributes: RestAttributes(startDate: start),
                content: content,
                pushType: nil
            )
        }

        let note = UNMutableNotificationContent()
        note.title = "휴식 끝!"
        note.body = info.isEmpty ? title : "다음: \(title) · \(info)"
        note.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        let request = UNNotificationRequest(identifier: notificationID, content: note, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func stop() async {
        for activity in Activity<RestAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
    }

    /// 지금 돌아가는 휴식 타이머 (앱을 다시 열었을 때 화면 복원용)
    static func current() -> (start: Date, end: Date, title: String)? {
        guard let activity = Activity<RestAttributes>.activities.first else { return nil }
        let state = activity.content.state
        return (activity.attributes.startDate, state.endDate, state.title)
    }

    static func requestPermissions() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }
}
