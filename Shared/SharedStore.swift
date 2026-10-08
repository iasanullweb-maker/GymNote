import Foundation
import WidgetKit
import Darwin

/// 앱과 위젯이 같이 쓰는 계정별 저장소. 인증 토큰은 이 컨테이너에 저장하지 않는다.
enum SharedStore {
    /// project.yml의 엔타이틀먼트와 같은 값이어야 함
    static let baseGroupID = "group.com.gymnote.app"
    static let fileName = "gymnote-data.json"

    #if DEBUG
    static var testingDirectory: URL?
    #endif

    /// AltStore는 다시 서명할 때 그룹 ID 뒤에 팀 ID를 붙이고(예: group.com.gymnote.app.ABCDE12345),
    /// 실제 ID를 Info.plist의 ALTAppGroups에 적어둠. 그래서 실행 중에 진짜 ID를 찾아서 씀.
    static let groupID: String? = resolveGroupID()

    static var directory: URL {
        #if DEBUG
        if let testingDirectory { return testingDirectory }
        #endif
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
    private static var catalogURL: URL { directory.appendingPathComponent("record-catalog.json") }

    static func recordCatalog() -> RecordCatalogCache? {
        try? locked {
            let raw = try Data(contentsOf: catalogURL)
            guard raw.count <= 2_000_000 else { throw CocoaError(.fileReadCorruptFile) }
            return try JSONDecoder().decode(RecordCatalogCache.self, from: raw)
        }
    }

    static func saveRecordCatalog(_ cache: RecordCatalogCache) throws {
        try locked { try write(cache, to: catalogURL) }
        WidgetCenter.shared.reloadAllTimelines()
    }
    private static var selectionURL: URL { directory.appendingPathComponent("active-account.json") }

    /// The lock covers selection, read/modify/write, and sync acknowledgements across app + widget.
    private static func locked<T>(_ action: () throws -> T) throws -> T {
        let lockURL = directory.appendingPathComponent("gymnote-store.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { flock(descriptor, LOCK_UN) }
        return try action()
    }

    private static func readSelection() throws -> StoreSelection {
        guard FileManager.default.fileExists(atPath: selectionURL.path) else { return StoreSelection(userID: nil) }
        return try JSONDecoder().decode(StoreSelection.self, from: Data(contentsOf: selectionURL))
    }

    static func selection() throws -> StoreSelection { try locked { try readSelection() } }

    private static func url(for userID: UUID?) -> URL {
        guard let id = userID else { return fileURL }
        return directory.appendingPathComponent("account-\(id.uuidString.lowercased()).json")
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let raw = try JSONEncoder().encode(value)
        guard raw.count <= 2_000_000 else { throw CocoaError(.fileWriteOutOfSpace) }
        // 잠긴 상태에서도 위젯이 읽을 수 있게: 재부팅 후 첫 잠금 해제부터 접근 가능 (로그인 토큰은 키체인에 따로 보관)
        try raw.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var protectedURL = url
        var properties = URLResourceValues()
        properties.isExcludedFromBackup = true
        // Account caches have a cloud backup; legacy guest records still need device backups.
        if url.lastPathComponent != fileName { try protectedURL.setResourceValues(properties) }
    }

    private static func readSnapshot(userID: UUID?) throws -> StoredWorkout {
        let file = url(for: userID)
        guard FileManager.default.fileExists(atPath: file.path) else {
            var initial = StoredWorkout(data: userID == nil ? .sample : .empty)
            initial.dirty = userID == nil
            try write(initial, to: file)
            return initial
        }
        let raw = try Data(contentsOf: file)
        guard raw.count <= 2_000_000 else { throw CocoaError(.fileReadCorruptFile) }
        let decoder = JSONDecoder()
        if let snapshot = try? decoder.decode(StoredWorkout.self, from: raw) { return snapshot }
        // Migrate legacy JSON only for the guest. Corrupt account caches must never become sample data.
        guard userID == nil,
              let fields = try JSONSerialization.jsonObject(with: raw) as? [String: Any],
              fields["data"] == nil, fields["revision"] == nil, fields["week"] != nil
        else { throw CocoaError(.fileReadCorruptFile) }
        let legacy = try decoder.decode(AppData.self, from: raw)
        let backup = directory.appendingPathComponent("guest-before-accounts.json")
        if !FileManager.default.fileExists(atPath: backup.path) { try write(legacy, to: backup) }
        let migrated = StoredWorkout(data: legacy)
        try write(migrated, to: file)
        return migrated
    }

    static func snapshot(userID: UUID?) throws -> StoredWorkout {
        try locked { try readSnapshot(userID: userID) }
    }

    @discardableResult
    static func activate(userID: UUID?) throws -> StoreSelection {
        let selection = try locked {
            // Returning to guest must hide the previous account even if the guest file is corrupt.
            relaxProtection()
            if userID != nil { _ = try readSnapshot(userID: userID) }
            let next = StoreSelection(userID: userID)
            try write(next, to: selectionURL)
            return next
        }
        WidgetCenter.shared.reloadAllTimelines()
        return selection
    }

    /// 예전 버전이 '잠금 해제 중에만 읽기'로 저장한 파일을 위젯이 읽을 수 있는 등급으로 바꿈
    private static func relaxProtection() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            try? fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                  ofItemAtPath: file.path)
        }
    }

    static func persistEdits(from base: AppData, to edited: AppData, selection: StoreSelection) throws -> AppData {
        let result = try locked {
            guard try readSelection() == selection else { throw CocoaError(.fileWriteUnknown) }
            var latest = try readSnapshot(userID: selection.userID)
            latest.data = latest.data.applyingEdits(from: base, to: edited)
            latest.dirty = true
            latest.revision = UUID()
            try write(latest, to: url(for: selection.userID))
            return latest.data
        }
        WidgetCenter.shared.reloadAllTimelines()
        return result
    }

    static func replaceWithCloud(_ cloud: AppData, version: Int64, revision: UUID, selection: StoreSelection) throws {
        try locked {
            guard try readSelection() == selection else { throw CocoaError(.fileWriteUnknown) }
            var latest = try readSnapshot(userID: selection.userID)
            guard latest.revision == revision else { throw CocoaError(.fileWriteUnknown) }
            if latest.dirty {
                try write(latest, to: directory.appendingPathComponent("backup-\(selection.scope)-\(UUID()).json"))
            }
            latest.data = cloud
            latest.serverVersion = version
            latest.dirty = false
            latest.revision = UUID()
            try write(latest, to: url(for: selection.userID))
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func acknowledge(version: Int64, revision: UUID, selection: StoreSelection) throws {
        try locked {
            guard try readSelection() == selection else { throw CocoaError(.fileWriteUnknown) }
            var latest = try readSnapshot(userID: selection.userID)
            latest.serverVersion = version
            if latest.revision == revision { latest.dirty = false }
            try write(latest, to: url(for: selection.userID))
        }
    }

    /// First login may queue an explicitly consented local import before the first cloud read.
    /// Preserve both originals and add local IDs to the server snapshot before attempting CAS.
    static func mergeInitialImport(_ cloud: AppData, version: Int64, revision: UUID, selection: StoreSelection) throws {
        try locked {
            guard selection.userID != nil, try readSelection() == selection else { throw CocoaError(.fileWriteUnknown) }
            var latest = try readSnapshot(userID: selection.userID)
            guard latest.revision == revision, latest.serverVersion == 0, latest.importedGuest else {
                throw CocoaError(.fileWriteUnknown)
            }
            try write(latest, to: directory.appendingPathComponent("backup-\(selection.scope)-\(UUID()).json"))
            try write(cloud, to: directory.appendingPathComponent("backup-\(selection.scope)-\(UUID()).json"))
            latest.data = cloud.importingGuest(latest.data)
            latest.serverVersion = version
            latest.dirty = true
            latest.revision = UUID()
            try write(latest, to: url(for: selection.userID))
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func backupCloud(_ data: AppData, selection: StoreSelection) throws {
        try locked {
            guard try readSelection() == selection else { throw CocoaError(.fileWriteUnknown) }
            try write(data, to: directory.appendingPathComponent("backup-\(selection.scope)-\(UUID()).json"))
        }
    }

    static func importGuest(selection: StoreSelection) throws {
        try locked {
            guard selection.userID != nil, try readSelection() == selection else { throw CocoaError(.fileWriteUnknown) }
            var account = try readSnapshot(userID: selection.userID)
            guard !account.importedGuest else { return }
            let guest = try readSnapshot(userID: nil)
            try write(guest, to: directory.appendingPathComponent("import-\(selection.scope).json"))
            account.data = account.data.importingGuest(guest.data)
            account.importedGuest = true
            account.dirty = true
            account.revision = UUID()
            try write(account, to: url(for: selection.userID))
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func eraseAccount(_ userID: UUID) throws {
        try locked {
            let scope = userID.uuidString.lowercased()
            for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                if file.lastPathComponent == "account-\(scope).json" || file.lastPathComponent == "import-\(scope).json"
                    || file.lastPathComponent.hasPrefix("backup-\(scope)-") {
                    try FileManager.default.removeItem(at: file)
                }
            }
        }
    }

    static func load() -> AppData {
        (try? locked { try readSnapshot(userID: readSelection().userID).data }) ?? .empty
    }

    /// Stale widget buttons carry a generation, so they cannot change a different account.
    static func completeSet(_ exerciseID: UUID, generation: String) throws {
        try locked {
            let selection = try readSelection()
            guard selection.generation.uuidString == generation else { return }
            var latest = try readSnapshot(userID: selection.userID)
            latest.data.completeSetFromWidget(exerciseID)
            latest.dirty = true
            latest.revision = UUID()
            try write(latest, to: url(for: selection.userID))
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 일상 알림의 '완료' 버튼. 다른 계정으로 바뀐 뒤 남은 알림은 generation이 달라 아무것도 바꾸지 않는다.
    /// 반환값: 기록했으면 최신 데이터와 generation.
    @discardableResult
    static func completeDailyFromNotification(itemID: UUID, day: String, generation: String, at now: Date = Date()) throws -> (AppData, String)? {
        guard let date = DayKey.date(fromKey: day) else { return nil }
        let result: (AppData, String)? = try locked {
            let selection = try readSelection()
            guard selection.generation.uuidString == generation else { return nil }
            var latest = try readSnapshot(userID: selection.userID)
            guard latest.data.markDailyComplete(itemID, on: date, at: now) else { return nil }
            latest.dirty = true
            latest.revision = UUID()
            try write(latest, to: url(for: selection.userID))
            return (latest.data, generation)
        }
        if result != nil { WidgetCenter.shared.reloadAllTimelines() }
        return result
    }

    static func widgetSnapshot() -> (AppData, String) {
        let catalog = recordCatalog()?.types ?? CatalogRecordType.defaults
        return (try? locked {
            let selection = try readSelection()
            var data = try readSnapshot(userID: selection.userID).data
            data.recordTypes = CatalogRecordType.sorted(catalog).filter(\.active).map(\.recordType)
            return (data, selection.generation.uuidString)
        }) ?? (.empty, "")
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
