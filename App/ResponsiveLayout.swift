import SwiftUI

/// Use the current window width, including iPad Split View and rotation.
private struct CompactLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var gymnoteCompactLayout: Bool {
        get { self[CompactLayoutKey.self] }
        set { self[CompactLayoutKey.self] = newValue }
    }
}

#Preview("iPhone 작은 화면 · 계획", traits: .fixedLayout(width: 320, height: 640)) {
    ResponsiveLayoutPreview(screen: .plan)
}

#Preview("iPhone · 실행", traits: .fixedLayout(width: 390, height: 844)) {
    ResponsiveLayoutPreview(screen: .workout)
}

#Preview("iPhone · 기록", traits: .fixedLayout(width: 390, height: 844)) {
    ResponsiveLayoutPreview(screen: .records)
}

#Preview("iPad · 계획", traits: .fixedLayout(width: 820, height: 1180)) {
    ResponsiveLayoutPreview(screen: .plan)
}

private struct ResponsiveLayoutPreview: View {
    enum Screen { case plan, workout, records }
    let screen: Screen
    @State private var date = Date()
    @State private var model = AppModel(previewData: AppData.sample)

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 4) {
                WorkspaceSwitcher(selection: .constant("운동")).padding(.horizontal)
                WorkoutStatusBanner(startedAt: Date().addingTimeInterval(-600),
                                    restStart: Date(), restEnd: Date().addingTimeInterval(90),
                                    finishTitle: "운동 마치기", onSkip: {}, onFinish: {})
                    .padding(.horizontal)
                Group {
                    switch screen {
                    case .plan: RoutineView(selectedDate: $date)
                    case .workout: TodayView()
                    case .records:
                        NavigationStack {
                            List {
                                ForEach(model.data.recordTypes) { type in
                                    RecordSection(type: type, onAdd: {})
                                }
                            }.navigationTitle("기록")
                        }
                    }
                }
            }
            .environment(\.gymnoteCompactLayout, geometry.size.width < 600)
        }
        .environment(model)
    }
}
