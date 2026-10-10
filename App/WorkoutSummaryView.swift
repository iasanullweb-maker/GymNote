import SwiftUI

struct WorkoutSummaryView: View {
    let summary: WorkoutSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("운동 일지에 저장됐어요", systemImage: "checkmark.circle.fill")
                .font(.headline).foregroundStyle(.green)
            Text(summary.session.plan.title).font(.title3.bold())
            Text("\(summary.session.done) / \(summary.session.total)세트 완료")
                .monospacedDigit()
            if let seconds = summary.duration {
                Text("운동 시간 \(RestDuration.text(seconds: seconds))")
            }
            if summary.recordedSets > 0 {
                Text("기록된 실제 횟수 \(summary.recordedReps)회")
                if summary.recordedSets < summary.session.done {
                    Text("\(summary.session.done)세트 중 \(summary.recordedSets)세트의 횟수만 합산했어요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("실제 횟수 미기록").foregroundStyle(.secondary)
            }
            if let change = summary.repetitionChange, let date = summary.previousDate {
                Text("\(date.formatted(.dateTime.month().day())) 같은 구성·무게 대비 \(change > 0 ? "+" : "")\(change)회")
                    .font(.subheadline)
            }
            Text("이 운동일까지 최근 7일 · \(summary.workoutDays)일 운동했어요")
                .font(.subheadline).foregroundStyle(.secondary)
            ForEach(summary.improvements, id: \.self) { improvement in
                Label("신기록 · \(improvement)", systemImage: "trophy.fill")
                    .font(.subheadline).foregroundStyle(.orange)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 6)
    }
}
