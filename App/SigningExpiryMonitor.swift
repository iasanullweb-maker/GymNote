import Foundation
import UserNotifications

/// 설치된 앱의 서명 만료일을 읽고, 만료 전 알림(48·24·3시간 전)을 예약한다.
/// AltStore에서 Refresh하면 만료일이 바뀌므로 앱을 열 때마다 다시 맞춘다.
/// 일상 알림 설정과 별개로 동작한다(서명이 만료되면 앱이 열리지 않기 때문).
enum SigningExpiryMonitor {
    /// embedded.mobileprovision이 없으면(시뮬레이터·개발 빌드) nil.
    static var expiration: Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return SigningExpiry.expirationDate(fromProvisioningProfile: data)
    }

    static func status(now: Date = Date()) -> SigningExpiry.Status? {
        expiration.map { SigningExpiry.status(expiration: $0, now: now) }
    }

    static func refreshReminders(now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let planned = expiration.map { SigningExpiry.reminders(expiration: $0, now: now) } ?? []
        let plannedIDs = Set(planned.map(\.id))
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(SigningExpiry.notificationPrefix) }
        // Refresh로 만료일이 바뀌면 예전 만료일 기준 알림을 지운다.
        let stale = pending.filter { !plannedIDs.contains($0) }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
        for reminder in planned where !pending.contains(reminder.id) {
            let content = UNMutableNotificationContent()
            content.title = "AltStore 갱신 필요"
            content.body = SigningExpiry.reminderBody(hoursLeft: reminder.hoursLeft)
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
            let request = UNNotificationRequest(identifier: reminder.id, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            try? await center.add(request)
        }
    }
}
