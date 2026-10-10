import Foundation

/// Server-owned definitions. IDs never overlap with the old, user-owned record types.
struct CatalogRecordType: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var unit: String
    var style: RecordType.Style
    var repsPerRound: Int
    var lowerIsBetter: Bool
    var hint: String
    var active: Bool
    var position: Int
    var revision: Int64

    var recordType: RecordType {
        RecordType(id: id, name: name, unit: unit, style: style, repsPerRound: repsPerRound,
                   lowerIsBetter: lowerIsBetter, hint: hint)
    }

    /// A new private workout snapshot; catalog edits never rewrite saved plans or history.
    func makeExercise() -> Exercise {
        let detail: String
        if style == .rounds { detail = "1라운드" }
        else {
            switch unit.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "회": detail = "10회"
            case "초": detail = "60초"
            case "분": detail = "1분"
            default: detail = ""
            }
        }
        return Exercise(name: name, sets: 3, detail: detail)
    }

    static let defaults: [CatalogRecordType] = RecordType.defaults.enumerated().map { index, type in
        CatalogRecordType(id: "common-\(type.id)-v1", name: type.name, unit: type.unit,
                          style: type.style, repsPerRound: type.repsPerRound,
                          lowerIsBetter: type.lowerIsBetter, hint: type.hint,
                          active: true, position: index, revision: 1)
    }

    static func sorted(_ types: [CatalogRecordType]) -> [CatalogRecordType] {
        types.sorted { $0.position == $1.position ? $0.id < $1.id : $0.position < $1.position }
    }
}

struct RecordCatalogCache: Codable {
    var project: String
    var types: [CatalogRecordType]
    var fetchedAt: Date
}

extension AppData {
    /// This is a display projection only. Never replace the private backup's legacy definitions.
    func recordDisplayTypes(catalog: [CatalogRecordType]) -> [RecordType] {
        let common = CatalogRecordType.sorted(catalog).map(\.recordType)
        let ids = Set(common.map(\.id))
        return common + recordTypes.filter { !ids.contains($0.id) }
    }
}
