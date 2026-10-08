import Foundation

/// 예약할 일상 알림 하나. 순수 계산 결과라 UserNotifications 없이 검사할 수 있다.
struct PlannedReminder: Equatable {
    enum Kind: String { case item, morning, evening }
    var id: String
    var fireDate: Date
    var title: String
    var body: String
    var kind: Kind
    var itemID: UUID?
    var day: String
}

extension AppData {
    static let reminderPrefix = "gymnote.daily."
    /// iOS는 앱당 예약 알림을 64개까지 보관한다. 휴식 타이머·'10분 뒤' 알림 자리를 남긴다.
    static let reminderLimit = 56
    static let reminderWindowDays = 14

    /// 오늘부터 `days`일 동안 울릴 일상 알림. 완료·건너뛴 날, 이미 지난 시각은 제외하고 가까운 순서로 `limit`개.
    func plannedReminders(now: Date = Date(), days: Int = AppData.reminderWindowDays,
                          limit: Int = AppData.reminderLimit, calendar: Calendar = .current) -> [PlannedReminder] {
        guard dailyReminders.enabled, days > 0, limit > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        var result: [PlannedReminder] = []
        for offset in 0..<days {
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: today),
                  let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: dayStart) else { continue }
            let key = DayKey.key(noon)
            let scheduled = dailyItems(on: noon)
            let remaining = scheduled.filter { !isDailyComplete($0, on: noon) }
            for item in remaining {
                guard let time = item.reminderTime, let fire = time.date(on: dayStart, calendar: calendar), fire > now else { continue }
                result.append(PlannedReminder(
                    id: "\(Self.reminderPrefix)item.\(item.id.uuidString).\(key)", fireDate: fire, title: item.title,
                    body: item.note.isEmpty ? (item.isRepeating ? "\(item.scheduleDescription) 일상" : "오늘 할 일") : item.note,
                    kind: .item, itemID: item.id, day: key))
            }
            guard !remaining.isEmpty else { continue }
            let names = Self.summaryNames(remaining)
            if let time = dailyReminders.morningSummary, let fire = time.date(on: dayStart, calendar: calendar), fire > now {
                result.append(PlannedReminder(id: "\(Self.reminderPrefix)morning.\(key)", fireDate: fire,
                    title: "오늘 일상 \(remaining.count)개", body: names, kind: .morning, itemID: nil, day: key))
            }
            if let time = dailyReminders.eveningCheck, let fire = time.date(on: dayStart, calendar: calendar), fire > now {
                result.append(PlannedReminder(id: "\(Self.reminderPrefix)evening.\(key)", fireDate: fire,
                    title: "아직 \(remaining.count)개 남았어요", body: names, kind: .evening, itemID: nil, day: key))
            }
        }
        result.sort { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
        return Array(result.prefix(limit))
    }

    private static func summaryNames(_ items: [DailyItem]) -> String {
        let names = items.prefix(4).map(\.title).joined(separator: ", ")
        return items.count > 4 ? "\(names) 외 \(items.count - 4)개" : names
    }
}
