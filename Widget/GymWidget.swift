import AppIntents
import SwiftUI
import WidgetKit

struct GymEntry: TimelineEntry {
    let date: Date
    let data: AppData
    var generation: String = ""
}

struct GymProvider: TimelineProvider {
    func placeholder(in context: Context) -> GymEntry {
        GymEntry(date: Date(), data: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (GymEntry) -> Void) {
        let snapshot = SharedStore.widgetSnapshot()
        completion(GymEntry(date: Date(), data: context.isPreview ? .sample : snapshot.0, generation: snapshot.1))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GymEntry>) -> Void) {
        let now = Date()
        let snapshot = SharedStore.widgetSnapshot()
        let entry = GymEntry(date: now, data: snapshot.0, generation: snapshot.1)
        // 자정이 지나면 다음 날 루틴으로 바꿈 (체크하면 앱/인텐트가 바로 새로고침함)
        let startOfToday = Calendar.current.startOfDay(for: now)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday) ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(tomorrow.addingTimeInterval(30))))
    }
}

struct GymWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GymEntry

    private var workoutDate: Date { entry.data.activeWorkout?.startedAt ?? entry.date }
    private var plan: DayPlan { entry.data.activeWorkout?.plan ?? entry.data.plan(for: entry.date) }
    private var exerciseLine: String {
        plan.exercises.map(\.name).joined(separator: " · ")
    }
    private var dayTitle: String {
        "\(DayKey.weekdayName(workoutDate)) · \(plan.isRestDay ? "휴식일" : plan.title)"
    }
    /// 그날 계획한 운동의 '한 세트 / 하루 총량' 최고기록 (운동이 없는 날은 기록 목록 위 종목)
    private var records: [RecordSummary] { entry.data.recordSummaries(on: workoutDate) }
    private var prLine: String {
        records.map { "\($0.name) \($0.setText)" + ($0.dayText.map { "/\($0)" } ?? "") }
            .joined(separator: " · ")
    }
    private func recordValue(_ summary: RecordSummary) -> String {
        summary.dayText.map { "세트 \(summary.setText) · 하루 \($0)" } ?? summary.setText
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(plan.isRestDay ? "휴식일" : "\(plan.title) · \(exerciseLine)")
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .systemSmall:
            small
        case .systemMedium:
            list(maxItems: 4)
        default:
            list(maxItems: 8)
        }
    }

    // MARK: 잠금 화면

    private var circular: some View {
        VStack(spacing: 2) {
            Image(systemName: "dumbbell")
            Text(plan.isRestDay ? "휴식" : plan.title)
                .font(.caption2)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(dayTitle)
                .font(.headline)
                .lineLimit(1)
            if !plan.isRestDay {
                Text(exerciseLine)
                    .font(.caption)
                    .lineLimit(1)
            }
            Text(prLine)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 홈 화면

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dayTitle)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if plan.isRestDay {
                Text("푹 쉬는 날")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(exerciseLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            ForEach(records) { summary in
                HStack {
                    Text(summary.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text(summary.dayText.map { "\(summary.setText)·\($0)" } ?? summary.setText)
                        .font(.caption.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .accessibilityLabel("\(summary.name) 최고기록 \(recordValue(summary))")
            }
        }
    }

    private func list(maxItems: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(dayTitle)
                    .font(.headline)
                    .lineLimit(1)
                if plan.isRestDay {
                    Text("오늘은 회복하는 날")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(plan.exercises.prefix(maxItems)) { exercise in
                        exerciseButton(exercise)
                    }
                    if plan.exercises.count > maxItems {
                        Text("+\(plan.exercises.count - maxItems)개 더")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("최고 기록")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(records) { summary in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(summary.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(recordValue(summary))
                            .font(.subheadline.bold())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                Spacer(minLength: 0)
                Button(intent: StartRestIntent(seconds: entry.data.defaultRest, generation: entry.generation)) {
                    Label(RestDuration.text(seconds: entry.data.defaultRest), systemImage: "timer")
                        .font(.caption.bold())
                }
                .tint(.orange)
            }
            .frame(width: 100, alignment: .leading)
        }
    }

    private func exerciseButton(_ exercise: Exercise) -> some View {
        let done = entry.data.doneSets(exercise, on: workoutDate)
        let finished = done >= exercise.sets
        return Button(intent: CompleteSetIntent(exerciseID: exercise.id.uuidString, generation: entry.generation)) {
            HStack(spacing: 6) {
                Image(systemName: finished ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(finished ? Color.green : Color.secondary)
                Text(exercise.name)
                    .font(.caption)
                    .lineLimit(1)
                    .strikethrough(finished)
                Spacer(minLength: 2)
                Text(exercise.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct GymWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GymWidget", provider: GymProvider()) { entry in
            GymWidgetView(entry: entry)
                .privacySensitive()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("오늘 운동")
        .description("오늘 운동 이름·횟수와 최고 기록, 운동 체크와 휴식 타이머")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
            .accessoryRectangular, .accessoryInline, .accessoryCircular,
        ])
    }
}
