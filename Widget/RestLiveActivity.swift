import ActivityKit
import SwiftUI
import WidgetKit

struct RestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestAttributes.self) { context in
            RestLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.8))
                .activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            let resting = context.state.isResting(at: Date(), stale: context.isStale)
            let working = context.state.workoutStartedAt != nil && !resting
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(resting ? "휴식 중" : working ? "운동 중" : "휴식 완료",
                          systemImage: resting || !working ? "timer" : "figure.strengthtraining.traditional")
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityTime(state: context.state, resting: resting)
                        .frame(width: 130, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("다음: \(context.state.title)")
                }
            } compactLeading: {
                Image(systemName: resting || !working ? "timer" : "figure.strengthtraining.traditional")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                ActivityTime(state: context.state, resting: resting)
                    .font(.caption2).frame(width: 72, alignment: .trailing)
            } minimal: {
                Image(systemName: resting || !working ? "timer" : "figure.strengthtraining.traditional")
            }
        }
    }
}

struct RestLockScreenView: View {
    let context: ActivityViewContext<RestAttributes>

    var body: some View {
        let resting = context.state.isResting(at: Date(), stale: context.isStale)
        let working = context.state.workoutStartedAt != nil && !resting
        HStack(spacing: 16) {
            Image(systemName: resting || !working ? "timer" : "figure.strengthtraining.traditional")
                .font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(resting ? "휴식 중" : working ? "운동 중" : "휴식 완료")
                    .font(.headline).foregroundStyle(.orange)
                Text("다음: \(context.state.title)")
                    .font(.subheadline).foregroundStyle(.white).lineLimit(1)
                if !context.state.info.isEmpty {
                    Text(context.state.info).font(.caption)
                        .foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                ActivityTime(state: context.state, resting: resting)
                    .font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .frame(width: 130, alignment: .trailing)
                Text(resting ? "남은 휴식" : working ? "운동 경과" : "")
                    .font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
        }.padding(16)
    }
}

/// System timer text keeps advancing when the app is suspended.
private struct ActivityTime: View {
    let state: RestAttributes.ContentState
    let resting: Bool

    var body: some View {
        Group {
            if resting {
                Text(timerInterval: (state.restStartedAt ?? Date())...state.endDate, countsDown: true)
            } else if let start = state.workoutStartedAt {
                Text(start, style: .timer)
            } else { Text("0초") }
        }
        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
    }
}
