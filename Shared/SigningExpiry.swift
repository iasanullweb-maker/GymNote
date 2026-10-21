import Foundation

/// AltStore(무료 Apple ID)로 서명한 앱은 7일 뒤 서명이 만료되어 열리지 않는다.
/// 앱 번들의 embedded.mobileprovision에 AltStore가 새로 넣은 만료일이 있으므로,
/// 그 날짜를 읽어 남은 기간을 보여 주고 만료 전에 미리 알린다.
/// 순수 Foundation 코드라 scripts/test_signing_expiry.swift에서 Linux/macOS 모두 검사한다.
enum SigningExpiry {
    /// 이 시간 이하로 남으면 '갱신 필요'로 강조한다.
    static let warningWindow: TimeInterval = 48 * 3600
    /// 만료 전 알림 시점(만료 시각 기준 몇 시간 전). 이미 지난 시점은 건너뛴다.
    static let reminderLeadHours = [48, 24, 3]
    static let notificationPrefix = "gymnote.signing."

    enum Level: Equatable { case ok, soon, expired }

    struct Status: Equatable {
        let expiration: Date
        let level: Level
        /// 만료까지 남은 시간(초). 지났으면 0.
        let remaining: TimeInterval
    }

    /// provisioning profile은 CMS 서명 안에 XML plist가 그대로 들어 있다. 그 부분만 잘라 읽는다.
    static func expirationDate(fromProvisioningProfile data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        else { return nil }
        return plist["ExpirationDate"] as? Date
    }

    static func status(expiration: Date, now: Date) -> Status {
        let remaining = expiration.timeIntervalSince(now)
        let level: Level = remaining <= 0 ? .expired : (remaining <= warningWindow ? .soon : .ok)
        return Status(expiration: expiration, level: level, remaining: max(0, remaining))
    }

    /// 예약할 알림: (식별자, 울릴 시각, 남은 시간 표시). 지금 이후의 것만.
    static func reminders(expiration: Date, now: Date) -> [(id: String, fireDate: Date, hoursLeft: Int)] {
        reminderLeadHours.compactMap { hours in
            let fire = expiration.addingTimeInterval(-Double(hours) * 3600)
            guard fire > now else { return nil }
            let stamp = Int(expiration.timeIntervalSince1970)
            return ("\(notificationPrefix)\(stamp).\(hours)h", fire, hours)
        }
    }

    /// "3일 5시간" / "5시간" / "40분" 형식. 0이면 "만료됨".
    static func remainingText(_ remaining: TimeInterval) -> String {
        guard remaining > 0 else { return "만료됨" }
        let minutes = Int(remaining / 60)
        let days = minutes / (24 * 60), hours = (minutes / 60) % 24
        if days > 0 { return hours > 0 ? "\(days)일 \(hours)시간" : "\(days)일" }
        if hours > 0 { return "\(hours)시간" }
        return "\(max(1, minutes))분"
    }

    static func reminderBody(hoursLeft: Int) -> String {
        let when = hoursLeft >= 24 ? "\(hoursLeft / 24)일" : "\(hoursLeft)시간"
        return "\(when) 뒤 앱 서명이 만료돼요. 노트북 AltServer를 켜고(학교망이면 VPN·USB) AltStore에서 Refresh All을 눌러 주세요."
    }
}
