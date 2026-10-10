import Foundation
import UserNotifications

/// 일상 알림을 iOS 로컬 알림으로 예약한다. 서버 없이 기기가 직접 울리며, 앞으로 2주치만 예약하고
/// 앱 실행·일상 변경·알림 버튼 처리 때마다 다시 맞춘다. 휴식 타이머 알림(`gymnote.rest.end`)은 건드리지 않는다.
enum DailyReminderScheduler {
    static let itemCategory = "gymnote.daily.item"
    static let summaryCategory = "gymnote.daily.summary"
    static let doneAction = "gymnote.daily.done"
    static let snoozeAction = "gymnote.daily.snooze"
    static let snoozePrefix = AppData.reminderPrefix + "snooze."
    static let snoozeMinutes = 10

    /// 알림을 길게 눌렀을 때의 버튼. '완료'는 앱을 열지 않고 기록한다.
    static func registerCategories() {
        let done = UNNotificationAction(identifier: doneAction, title: "완료", options: [])
        let snooze = UNNotificationAction(identifier: snoozeAction, title: "\(snoozeMinutes)분 뒤 다시", options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: itemCategory, actions: [done, snooze], intentIdentifiers: []),
            UNNotificationCategory(identifier: summaryCategory, actions: [], intentIdentifiers: []),
        ])
    }

    // MARK: 이 기기에서 알림 받기 (기기별, 서버에 올리지 않음)

    /// 같은 계정을 여러 기기에서 쓰면 일상 알림이 기기마다 울리므로 기기별로 끄고 켠다.
    static let devicePreferenceKey = "gymnote.dailyReminders.thisDevice"

    static var enabledOnThisDevice: Bool {
        UserDefaults.standard.object(forKey: devicePreferenceKey) as? Bool ?? false
    }

    /// 처음 한 번만 기본값을 정한다. 이미 쓰던 기기(저장 파일이 있음)는 켜 두고, 새로 설치한 기기는 꺼 둔다.
    /// 앱이 저장 파일을 만들기 전에 불러야 한다.
    static func prepareDevicePreference() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: devicePreferenceKey) == nil else { return }
        let fm = FileManager.default
        let existing = fm.fileExists(atPath: SharedStore.fileURL.path)
            || fm.fileExists(atPath: SharedStore.directory.appendingPathComponent("active-account.json").path)
        defaults.set(existing, forKey: devicePreferenceKey)
    }

    @MainActor private static var running: Task<Void, Never>?

    /// 변경이 몰려도 순서대로 한 번씩 적용한다.
    @MainActor static func refresh(data: AppData, generation: String) {
        let previous = running
        running = Task {
            await previous?.value
            await apply(data: data, generation: generation)
        }
    }

    static func apply(data: AppData, generation: String, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        // 이 기기에서 끄면 계획이 비어 예약된 일상 알림이 모두 지워진다(휴식 타이머 알림은 그대로).
        let plan = enabledOnThisDevice ? data.plannedReminders(now: now) : []
        let planned = Dictionary(uniqueKeysWithValues: plan.map { ($0.id, $0) })
        let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(AppData.reminderPrefix) }

        // 계획에 없는 일상 알림(완료·삭제·다른 계정·꺼짐)은 지운다. '10분 뒤' 알림은 아직 할 일이면 남긴다.
        var stale: [String] = []
        var unchanged = Set<String>()
        for request in pending {
            if request.identifier.hasPrefix(snoozePrefix) {
                if !snoozeStillNeeded(request, data: data, generation: generation) { stale.append(request.identifier) }
            } else if let wanted = planned[request.identifier], matches(request, wanted, data: data, generation: generation) {
                unchanged.insert(request.identifier)
            } else if planned[request.identifier] == nil {
                stale.append(request.identifier)
            }
        }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
        for reminder in plan where !unchanged.contains(reminder.id) {
            let request = UNNotificationRequest(identifier: reminder.id,
                                                content: content(for: reminder, data: data, generation: generation),
                                                trigger: trigger(for: reminder.fireDate))
            try? await center.add(request) // 같은 식별자는 교체된다.
        }
    }

    /// 알림의 '10분 뒤 다시'. 같은 내용으로 한 번 더 예약한다.
    static func snooze(_ original: UNNotificationContent) async {
        guard let itemID = original.userInfo["itemID"] as? String, let day = original.userInfo["day"] as? String,
              let copy = original.mutableCopy() as? UNMutableNotificationContent else { return }
        let request = UNNotificationRequest(
            identifier: "\(snoozePrefix)\(itemID).\(day)", content: copy,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(snoozeMinutes * 60), repeats: false))
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// 완료한 항목은 알림 센터에 남은 알림도 정리한다.
    static func removeDelivered(itemID: UUID, day: String) async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.deliveredNotifications().map(\.request.identifier).filter {
            $0.hasPrefix(AppData.reminderPrefix) && $0.contains(itemID.uuidString) && $0.hasSuffix(day)
        }
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private static func content(for reminder: PlannedReminder, data: AppData, generation: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = data.dailyReminders.sound ? .default : nil
        content.threadIdentifier = "gymnote.daily"
        content.categoryIdentifier = reminder.kind == .item ? itemCategory : summaryCategory
        var info: [String: Any] = ["day": reminder.day, "generation": generation, "kind": reminder.kind.rawValue]
        if let id = reminder.itemID { info["itemID"] = id.uuidString }
        content.userInfo = info
        return content
    }

    private static func trigger(for date: Date) -> UNCalendarNotificationTrigger {
        UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date), repeats: false)
    }

    private static func matches(_ request: UNNotificationRequest, _ reminder: PlannedReminder, data: AppData, generation: String) -> Bool {
        let content = request.content
        guard content.title == reminder.title, content.body == reminder.body,
              (content.sound != nil) == data.dailyReminders.sound,
              content.userInfo["generation"] as? String == generation,
              let trigger = request.trigger as? UNCalendarNotificationTrigger else { return false }
        return trigger.dateComponents == Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
    }

    private static func snoozeStillNeeded(_ request: UNNotificationRequest, data: AppData, generation: String) -> Bool {
        let info = request.content.userInfo
        guard enabledOnThisDevice, data.dailyReminders.enabled, info["generation"] as? String == generation,
              let id = (info["itemID"] as? String).flatMap(UUID.init(uuidString:)),
              let day = info["day"] as? String, let date = DayKey.date(fromKey: day),
              let item = data.dailyItems.first(where: { $0.id == id }) else { return false }
        return !data.isDailyComplete(item, on: date)
    }
}
