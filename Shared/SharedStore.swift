import Foundation
import WidgetKit

/// 앱과 위젯이 같이 쓰는 저장소 (App Group 컨테이너 안의 JSON 파일 하나)
enum SharedStore {
    /// project.yml의 엔타이틀먼트와 같은 값이어야 함
    static let baseGroupID = "group.com.gymnote.app"
    static let fileName = "gymnote-data.json"

    /// AltStore는 다시 서명할 때 그룹 ID 뒤에 팀 ID를 붙이고(예: group.com.gymnote.app.ABCDE12345),
    /// 실제 ID를 Info.plist의 ALTAppGroups에 적어둠. 그래서 실행 중에 진짜 ID를 찾아서 씀.
    static let groupID: String? = resolveGroupID()

    static var directory: URL {
        if let id = groupID,
           let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
            return url
        }
        // 그룹을 못 찾으면 각자 저장 (앱은 동작하지만 위젯과 공유 안 됨)
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var fileURL: URL { directory.appendingPathComponent(fileName) }

    static func load() -> AppData {
        let url = fileURL
        guard let raw = try? Data(contentsOf: url) else {
            let initial = AppData.sample
            save(initial, reloadWidgets: false)
            return initial
        }
        if let decoded = try? JSONDecoder().decode(AppData.self, from: raw) {
            // 이전 요일 루틴을 날짜 일정으로 옮긴 결과를 즉시 저장해 다음 주에 다시 이관하지 않음.
            if let fields = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
               fields["scheduledPlans"] == nil || fields["exerciseLibrary"] == nil {
                save(decoded, reloadWidgets: false)
            }
            return decoded
        }
        // 파일이 깨졌으면 덮어쓰기 전에 백업
        let backup = directory.appendingPathComponent("gymnote-data.broken.json")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: url, to: backup)
        return AppData.sample
    }

    static func save(_ appData: AppData, reloadWidgets: Bool = true) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let raw = try? encoder.encode(appData) {
            try? raw.write(to: fileURL, options: .atomic)
        }
        if reloadWidgets {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    static var diagnostics: String {
        if let id = groupID { return "연결됨 · \(id)" }
        return "연결 안 됨 (위젯과 공유 불가)"
    }

    // MARK: - 그룹 ID 찾기

    private static func resolveGroupID() -> String? {
        var candidates: [String] = []

        if let altGroups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] {
            candidates += altGroups.filter { $0.hasPrefix(baseGroupID) }
        }
        candidates += provisioningProfileGroups().filter { $0.hasPrefix(baseGroupID) }
        candidates.append(baseGroupID)

        let fm = FileManager.default
        return candidates.first { fm.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }
    }

    /// 앱 안에 들어있는 프로비저닝 프로파일에서 App Group 목록을 읽음 (예비 수단)
    private static func provisioningProfileGroups() -> [String] {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let raw = try? Data(contentsOf: url),
              let start = raw.range(of: Data("<?xml".utf8)),
              let end = raw.range(of: Data("</plist>".utf8), in: start.lowerBound..<raw.endIndex)
        else { return [] }

        let plistData = raw.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String]
        else { return [] }
        return groups
    }
}
