import ActivityKit
import SwiftUI
import WidgetKit

/// 잠금 화면에 뜨는 휴식 타이머
struct RestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestAttributes.self) { context in
            RestLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            // 아이패드엔 다이나믹 아일랜드가 없지만 API상 필요
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("휴식", systemImage: "timer")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.attributes.startDate...context.state.endDate, countsDown: true)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("다음: \(context.state.title)")
                }
            } compactLeading: {
                Image(systemName: "timer")
            } compactTrailing: {
                Text(timerInterval: context.attributes.startDate...context.state.endDate, countsDown: true)
                    .monospacedDigit()
                    .frame(maxWidth: 48)
            } minimal: {
                Image(systemName: "timer")
            }
        }
    }
}

struct RestLockScreenView: View {
    let context: ActivityViewContext<RestAttributes>

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.isStale ? "휴식 끝!" : "휴식 중")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                Text("다음: \(context.state.title)")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !context.state.info.isEmpty {
                    Text(context.state.info)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(timerInterval: context.attributes.startDate...context.state.endDate, countsDown: true)
                .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
                .frame(width: 140, alignment: .trailing)
        }
        .padding(16)
    }
}
