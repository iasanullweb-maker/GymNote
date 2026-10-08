import SwiftUI
import WidgetKit

struct DailyProvider: TimelineProvider {
    private var previewEntry: GymEntry {
        let now = Date()
        var data = AppData.empty
        data.saveDailyItem(DailyItem(title: "과제 제출", note: "보고서 확인하기", scheduledDate: now))
        data.saveDailyItem(DailyItem(title: "독서 20분", kind: .habit, startDate: now))
        data.saveDailyItem(DailyItem(title: "책상 정리"))
        return GymEntry(date: now, data: data)
    }

    func placeholder(in context: Context) -> GymEntry { previewEntry }

    func getSnapshot(in context: Context, completion: @escaping (GymEntry) -> Void) {
        if context.isPreview { completion(previewEntry) }
        else { GymProvider().getSnapshot(in: context, completion: completion) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GymEntry>) -> Void) {
        // 운동 위젯과 같은 계정 스냅샷과 자정 갱신 정책을 사용한다.
        GymProvider().getTimeline(in: context, completion: completion)
    }
}

struct DailyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GymEntry

    private var scheduled: [DailyItem] { entry.data.dailyItems(on: entry.date) }
    private var remaining: [DailyItem] {
        scheduled.filter { !entry.data.isDailyComplete($0, on: entry.date) }
    }
    private var undated: [DailyItem] {
        entry.data.dailyItems.filter {
            $0.kind == .task && $0.scheduledDate == nil
                && !entry.data.isDailyComplete($0, on: entry.date)
        }
    }
    private var items: [DailyItem] { remaining + undated }
    private var status: String {
        if scheduled.isEmpty { return "오늘 예정 없음" }
        if remaining.isEmpty { return "오늘 일상 모두 완료" }
        return "오늘 \(remaining.count)개 남음"
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(items.first.map { "\(isUndated($0) ? "미정" : "일상") · \($0.title)" } ?? status)
        case .accessoryCircular:
            VStack(spacing: 2) {
                Image(systemName: "checklist")
                Text(remaining.isEmpty ? (scheduled.isEmpty ? "없음" : "완료") : "\(remaining.count)개")
                    .font(.caption.bold())
                if !remaining.isEmpty { Text("남음").font(.caption2) }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(status).font(.headline).lineLimit(1)
                ForEach(items.prefix(2)) { item in
                    Text(isUndated(item) ? "미정 · \(item.title)" : item.title)
                        .font(.caption).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemSmall:
            list(maxItems: 2, showNotes: false)
        case .systemMedium:
            list(maxItems: 3, showNotes: false)
        default:
            list(maxItems: 6, showNotes: true)
        }
    }

    private func isUndated(_ item: DailyItem) -> Bool {
        item.kind == .task && item.scheduledDate == nil
    }

    private func list(maxItems: Int, showNotes: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("오늘 일상", systemImage: "checklist")
                    .font(.headline)
                Spacer(minLength: 0)
                Text(DayKey.weekdayName(entry.date)).font(.caption).foregroundStyle(.secondary)
            }
            Text(status).font(.caption).foregroundStyle(.secondary)
            ForEach(items.prefix(maxItems)) { item in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: item.kind == .habit ? "arrow.triangle.2.circlepath" : "circle")
                        .foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).lineLimit(1)
                        if showNotes, !item.note.isEmpty {
                            Text(item.note).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(isUndated(item) ? "미정" : (item.reminderTime?.label ?? item.kind.title))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            if items.count > maxItems {
                Text("+\(items.count - maxItems)개 더").font(.caption2).foregroundStyle(.secondary)
            }
            if items.isEmpty {
                Text(scheduled.isEmpty ? "앱에서 일상을 추가해 보세요." : "오늘 예정된 일을 모두 마쳤어요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DailyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DailyWidget", provider: DailyProvider()) { entry in
            DailyWidgetView(entry: entry)
                .privacySensitive()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("오늘 일상")
        .description("오늘 남은 일상과 날짜 미정 일상을 확인해요.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
            .accessoryRectangular, .accessoryInline, .accessoryCircular,
        ])
    }
}
