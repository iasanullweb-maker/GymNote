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
                    RestActivityCountdown(end: context.state.endDate, finished: context.isStale)
                        .frame(width: 130, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("다음: \(context.state.title)")
                }
            } compactLeading: {
                Image(systemName: "timer")
            } compactTrailing: {
                RestActivityCountdown(end: context.state.endDate, finished: context.isStale)
                    .font(.caption2)
                    .frame(width: 72, alignment: .trailing)
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
            RestActivityCountdown(end: context.state.endDate, finished: context.isStale)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
                .frame(width: 180, alignment: .trailing)
        }
        .padding(16)
    }
}

/// 시스템의 relative 표시는 앱이 멈춰 있어도 갱신된다.
/// staleDate (= end) 이후에는 경과 시간이 늘어나지 않도록 0초로 고정한다.
private struct RestActivityCountdown: View {
    let end: Date
    let finished: Bool

    var body: some View {
        Group {
            if finished { Text("0초") }
            else { Text(end, style: .relative) }
        }
        .environment(\.locale, Locale(identifier: "ko_KR"))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}
