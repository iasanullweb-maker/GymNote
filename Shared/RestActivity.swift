import ActivityKit
import Foundation
import UserNotifications

/// One Live Activity follows the workout through exercise and rest.
struct RestAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var endDate: Date
        var title: String
        var info: String
        var workoutStartedAt: Date? = nil
        var restStartedAt: Date? = nil

        func isResting(at date: Date, stale: Bool = false) -> Bool {
            !stale && endDate > date && (restStartedAt != nil || workoutStartedAt == nil)
        }
    }
    var startDate: Date
    var generation: String? = nil
}

@MainActor
enum RestController {
    static let notificationID = "gymnote.rest.end"
    private static var revision = UUID()
    private static var pendingRequest: UNNotificationRequest?

    /// Widget/Siri rest requests include the active workout when present.
    static func start(seconds: Int, title: String, info: String, sound: Bool = false, generation: String? = nil) async {
        guard let selection = try? SharedStore.selection() else { return }
        let owner = generation ?? selection.generation.uuidString
        guard owner == selection.generation.uuidString else { return }
        let workout = (try? SharedStore.snapshot(userID: selection.userID).data)?.activeWorkout
        let start = Date()
        await update(workoutStartedAt: workout?.startedAt, restStart: start,
                     restEnd: start.addingTimeInterval(TimeInterval(max(seconds, 5))),
                     title: title, info: info, generation: owner, notify: true, sound: sound)
    }

    static func update(workoutStartedAt: Date?, restStart: Date?, restEnd: Date?,
                       title: String, info: String, generation: String, notify: Bool = false, sound: Bool = false) async {
        guard !Task.isCancelled, (try? SharedStore.selection().generation.uuidString) == generation else { return }
        let operation = UUID()
        revision = operation
        let now = Date()
        let resting = restStart != nil && restEnd.map { $0 > now } == true
        let center = UNUserNotificationCenter.current()
        if !resting {
            pendingRequest = nil
            center.removePendingNotificationRequests(withIdentifiers: [notificationID])
            center.removeDeliveredNotifications(withIdentifiers: [notificationID])
        }
        guard workoutStartedAt != nil || resting else { await stop(); return }
        let state = RestAttributes.ContentState(endDate: restEnd ?? now, title: title, info: info,
                                                workoutStartedAt: workoutStartedAt, restStartedAt: resting ? restStart : nil)
        let content = ActivityContent(state: state, staleDate: resting ? restEnd : nil)
        var existing: Activity<RestAttributes>?
        for activity in Activity<RestAttributes>.activities {
            if existing == nil, activity.attributes.generation == generation {
                existing = activity
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        guard revision == operation, !Task.isCancelled,
              (try? SharedStore.selection().generation.uuidString) == generation else { return }
        if let existing {
            await existing.update(content)
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            _ = try? Activity<RestAttributes>.request(
                attributes: RestAttributes(startDate: restStart ?? workoutStartedAt ?? now, generation: generation),
                content: content, pushType: nil)
        }
        guard revision == operation, !Task.isCancelled,
              (try? SharedStore.selection().generation.uuidString) == generation else { return }
        if notify, resting, let end = restEnd {
            let note = UNMutableNotificationContent()
            note.title = "휴식 끝!"
            note.body = info.isEmpty ? title : "다음: \(title) · \(info)"
            note.sound = sound ? .default : nil
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
            let request = UNNotificationRequest(identifier: notificationID, content: note, trigger: trigger)
            pendingRequest = request
            try? await center.add(request)
            if revision != operation {
                // An older awaited add must not replace a newer timer or revive a skipped one.
                if let current = pendingRequest { try? await center.add(current) }
                else { center.removePendingNotificationRequests(withIdentifiers: [notificationID]) }
            } else if (try? SharedStore.selection().generation.uuidString) != generation {
                center.removePendingNotificationRequests(withIdentifiers: [notificationID])
            }
        }
    }

    static func stop() async {
        let operation = UUID()
        revision = operation
        pendingRequest = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationID])
        for activity in Activity<RestAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
            guard revision == operation else { return }
        }
    }

    static func current() -> (start: Date, end: Date, title: String)? {
        guard let owner = try? SharedStore.selection().generation.uuidString,
              let activity = Activity<RestAttributes>.activities.first(where: {
                  $0.attributes.generation == nil || $0.attributes.generation == owner
              }) else { return nil }
        let state = activity.content.state
        guard state.workoutStartedAt == nil || state.restStartedAt != nil else { return nil }
        return (state.restStartedAt ?? activity.attributes.startDate, state.endDate, state.title)
    }

    static func requestPermissions() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }
}
