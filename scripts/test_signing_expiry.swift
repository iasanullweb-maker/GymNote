import Foundation

/// SigningExpiry 회귀 검사: provisioning profile 만료일 읽기, 상태 단계, 알림 예약 시점, 표시 문구.
@main
struct SigningExpiryChecks {
    static func main() throws {
        let expiration = Date(timeIntervalSince1970: 1_793_000_000)

        // 1. CMS 서명 바이트 사이에 들어 있는 XML plist에서 ExpirationDate를 읽는다.
        let plist: [String: Any] = ["Name": "AltStore com.gymnote.app", "ExpirationDate": expiration,
                                    "Entitlements": ["application-identifier": "TEAM.com.gymnote.app"]]
        let xml = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        var profile = Data([0x30, 0x82, 0x0f, 0x3c, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x02])
        profile.append(xml)
        profile.append(contentsOf: [0xa0, 0x82, 0x0b, 0x66, 0x30, 0x82, 0x04, 0x00, 0xff, 0x00])
        let parsed = SigningExpiry.expirationDate(fromProvisioningProfile: profile)
        assert(parsed.map { abs($0.timeIntervalSince(expiration)) < 1 } == true, "만료일을 읽어야 함")
        assert(SigningExpiry.expirationDate(fromProvisioningProfile: Data([0x30, 0x82, 0x00])) == nil, "plist 없으면 nil")
        let noDate = try PropertyListSerialization.data(fromPropertyList: ["Name": "x"], format: .xml, options: 0)
        assert(SigningExpiry.expirationDate(fromProvisioningProfile: noDate) == nil, "ExpirationDate 없으면 nil")
        let truncated = xml.prefix(xml.count / 2)
        assert(SigningExpiry.expirationDate(fromProvisioningProfile: Data(truncated)) == nil, "잘린 plist는 nil")

        // 2. 상태 단계: 48시간 초과 ok, 이하 soon, 지나면 expired(남은 시간 0).
        let hour: TimeInterval = 3600
        assert(SigningExpiry.status(expiration: expiration, now: expiration - 5 * 24 * hour).level == .ok)
        assert(SigningExpiry.status(expiration: expiration, now: expiration - 48 * hour - 1).level == .ok)
        assert(SigningExpiry.status(expiration: expiration, now: expiration - 48 * hour).level == .soon)
        assert(SigningExpiry.status(expiration: expiration, now: expiration - 60).level == .soon)
        let expired = SigningExpiry.status(expiration: expiration, now: expiration + 10)
        assert(expired.level == .expired && expired.remaining == 0)
        assert(SigningExpiry.status(expiration: expiration, now: expiration).level == .expired)

        // 3. 알림: 48·24·3시간 전 중 지금 이후만, 만료일이 바뀌면 식별자도 바뀐다.
        let all = SigningExpiry.reminders(expiration: expiration, now: expiration - 7 * 24 * hour)
        assert(all.map(\.hoursLeft) == [48, 24, 3])
        assert(all.allSatisfy { $0.id.hasPrefix(SigningExpiry.notificationPrefix) })
        assert(Set(all.map(\.id)).count == 3)
        assert(abs(all[0].fireDate.timeIntervalSince(expiration - 48 * hour)) < 1)
        let late = SigningExpiry.reminders(expiration: expiration, now: expiration - 10 * hour)
        assert(late.map(\.hoursLeft) == [3], "지난 알림 시점은 건너뜀")
        assert(SigningExpiry.reminders(expiration: expiration, now: expiration - hour).isEmpty)
        let refreshed = SigningExpiry.reminders(expiration: expiration + 7 * 24 * hour, now: expiration - 7 * 24 * hour)
        assert(Set(refreshed.map(\.id)).isDisjoint(with: all.map(\.id)), "Refresh 후 새 만료일은 다른 식별자")
        // 일상 알림 정리(gymnote.daily.)가 서명 알림을 지우지 않도록 접두어가 겹치면 안 된다.
        assert(!SigningExpiry.notificationPrefix.hasPrefix("gymnote.daily."))

        // 4. 표시 문구.
        assert(SigningExpiry.remainingText(0) == "만료됨")
        assert(SigningExpiry.remainingText(-5) == "만료됨")
        assert(SigningExpiry.remainingText(30) == "1분")
        assert(SigningExpiry.remainingText(40 * 60) == "40분")
        assert(SigningExpiry.remainingText(5 * hour + 59) == "5시간")
        assert(SigningExpiry.remainingText(3 * 24 * hour) == "3일")
        assert(SigningExpiry.remainingText(3 * 24 * hour + 5 * hour) == "3일 5시간")
        assert(SigningExpiry.reminderBody(hoursLeft: 48).hasPrefix("2일 뒤"))
        assert(SigningExpiry.reminderBody(hoursLeft: 3).hasPrefix("3시간 뒤"))
        print("signing expiry checks passed")
    }
}
