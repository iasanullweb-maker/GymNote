import SwiftUI

struct CoachmarkStep {
    let target: String
    let title: String
    let message: String
}

struct TabCoachTour {
    let id: String
    let steps: [CoachmarkStep]

    static let planEditor = Self(id: "workout.plan.editor", steps: [
        .init(target: "plan.add", title: "운동을 더해요", message: "운동을 고르거나 기본 루틴을 추가해요. 기존 운동은 유지돼요."),
        .init(target: "plan.exercises", title: "세트와 순서를 바꿔요", message: "운동을 눌러 수정하고, 왼쪽으로 밀어 삭제해요. 순서 편집으로 순서를 바꿔요."),
        .init(target: "plan.replace", title: "계획 전체를 바꿔요", message: "다른 날짜나 요일의 계획을 가져오고, 확인한 뒤 교체해요.")
    ])
    static let exercisePicker = Self(id: "workout.exercise.picker", steps: [
        .init(target: "exercise.library", title: "저장한 운동을 골라요", message: "내 운동 목록의 세트·횟수를 복사해요. 원본은 바뀌지 않아요."),
        .init(target: "exercise.catalog", title: "새 종목도 추가해요", message: "운동 종목을 고르면 세트·횟수 설정으로 이어져요.")
    ])
    static func exerciseSettings(cindy: Bool) -> Self {
        Self(id: cindy ? "workout.exercise.cindy" : "workout.exercise.settings", steps: [
            .init(target: "exercise.settings", title: cindy ? "신디 목표를 정해요" : "내 목표를 정해요",
                  message: cindy ? "목표 세트 수를 정해요. 한 세트의 운동 구성은 아래에 있어요." : "세트 수와 목표 횟수·시간을 정해요. 세트별로 횟수를 다르게 설정할 수도 있어요."),
            .init(target: "exercise.save", title: "저장해서 적용해요", message: "저장을 누르면 설정한 목표가 계획에 반영돼요.")
        ])
    }
    static let planCopy = Self(id: "workout.plan.copy", steps: [
        .init(target: "plan.source", title: "가져올 계획을 골라요", message: "운동이 있는 다른 날짜나 요일을 골라요. 다음 화면에서 교체할 내용을 확인해요.")
    ])
    static let starter = Self(id: "workout.plan.starter", steps: [
        .init(target: "starter.conditions", title: "운동 조건을 골라요", message: "기구·경험·시간을 고르고 미리보기를 확인한 뒤 계획에 추가해요.")
    ])
    static let dailyEditor = Self(id: "daily.item.editor", steps: [
        .init(target: "daily.content", title: "할 일을 적어요", message: "이름과 메모를 입력해요. 저장한 일상도 여기서 수정해요."),
        .init(target: "daily.schedule", title: "날짜와 반복을 정해요", message: "한 번 할 일은 날짜를 정하고, 습관은 반복을 골라요. 알림도 설정할 수 있어요.")
    ])

    static func tour(tab: Int, daily: Bool) -> Self {
        let scope = daily ? "daily" : "workout"
        switch tab {
        case 0:
            return Self(id: "\(scope).today", steps: [
                .init(target: daily ? "daily.add" : "workout.start",
                      title: daily ? "오늘 할 일을 추가해요" : "오늘 운동을 시작해요",
                      message: daily ? "+ 버튼으로 할 일이나 습관을 추가하세요." : "시작한 뒤 세트를 하나씩 체크하세요."),
                .init(target: "workspace", title: "운동과 일상을 바꿔요",
                      message: "여기서 두 공간을 오갈 수 있어요.")
            ])
        case 1:
            var steps = [CoachmarkStep(target: "\(scope).calendar", title: "날짜를 길게 눌러요",
                message: daily ? "그날의 일상을 추가하거나 확인하세요." : "그날의 운동 계획을 만들 수 있어요.")]
            if !daily {
                steps.append(.init(target: "workout.plan", title: "계획은 여기서도 열어요",
                    message: "날짜를 고른 뒤 이 버튼을 누르세요."))
            }
            return Self(id: "\(scope).plans", steps: steps)
        case 2:
            return Self(id: "\(scope).records", steps: [
                .init(target: daily ? "daily.history" : "workout.records",
                      title: daily ? "완료한 일상을 돌아봐요" : "보고 싶은 기록을 골라요",
                      message: daily ? "이번 주 완료 개수와 지난 기록을 확인하세요." : "운동 일지·친구 순위·최고 기록을 볼 수 있어요.")
            ])
        case 3:
            return Self(id: "friends", steps: [
                .init(target: "friends.add", title: "친구와 함께 운동해요",
                      message: "로그인하고 닉네임을 정하면 친구 코드로 연결할 수 있어요.")
            ])
        default:
            return Self(id: "settings", steps: [
                .init(target: "settings.rest", title: "세트 사이 휴식을 정해요",
                      message: "여기나 실행 탭의 휴식 타이머 휠에서 휴식 시간을 정하세요.")
            ])
        }
    }
}

/// Completion belongs to the account; replay deliberately uses only this app session.
enum CoachmarkHistory {
    static func shouldPresent(_ id: String, completed: [String], accountReady: Bool,
                              replayCompleted: Set<String>? = nil) -> Bool {
        if let replayCompleted { return !replayCompleted.contains(id) }
        return accountReady && !completed.contains(id)
    }
}

struct CoachmarkPresentation: Equatable {
    let card: CGRect
    let highlightsTarget: Bool
}

private struct CoachmarkCardObserverKey: EnvironmentKey {
    static let defaultValue: ((CoachmarkPresentation) -> Void)? = nil
}

private struct CoachmarkReporterKey: EnvironmentKey {
    static let defaultValue: ((String, UUID, CGRect?) -> Void)? = nil
}

extension EnvironmentValues {
    var coachmarkCardObserver: ((CoachmarkPresentation) -> Void)? {
        get { self[CoachmarkCardObserverKey.self] }
        set { self[CoachmarkCardObserverKey.self] = newValue }
    }

    fileprivate var coachmarkReporter: ((String, UUID, CGRect?) -> Void)? {
        get { self[CoachmarkReporterKey.self] }
        set { self[CoachmarkReporterKey.self] = newValue }
    }
}

/// Toolbar and TabView children do not reliably bubble Anchor preferences to RootView.
/// Report measured global frames through the environment instead, then convert at the host.
private struct CoachmarkTarget: ViewModifier {
    let id: String
    let enabled: Bool
    @State private var token = UUID()
    @Environment(\.coachmarkReporter) private var report

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                enabled ? proxy.frame(in: .global) : .null
            } action: { frame in
                report?(id, token, frame.isNull || frame.isEmpty ? nil : frame)
            }
            .onDisappear { report?(id, token, nil) }
    }
}

extension View {
    func coachmarkTarget(_ id: String, enabled: Bool = true) -> some View {
        modifier(CoachmarkTarget(id: id, enabled: enabled))
    }

    func tabCoachmarks(_ tour: TabCoachTour, enabled: Bool = true) -> some View {
        modifier(TabCoachmarkHost(tour: tour, enabled: enabled))
    }
}

private struct TabCoachmarkHost: ViewModifier {
    let tour: TabCoachTour
    let enabled: Bool
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    @State private var progressID = ""
    @State private var index = 0
    @State private var targets: [String: [UUID: CGRect]] = [:]

    private var pending: Bool {
        guard enabled else { return false }
        // The first server read must finish before deciding on a new device.
        let ready = model.selection.userID != nil && account.user?.id == model.selection.userID
            && account.cloudChecked && !account.busy && account.conflict == nil
        return CoachmarkHistory.shouldPresent(tour.id, completed: model.data.completedCoachmarks,
            accountReady: ready,
            replayCompleted: model.replayingCoachmarks ? model.replayCompletedCoachmarks : nil)
    }
    private var currentIndex: Int { progressID == tour.id ? index : 0 }

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!pending)
            .accessibilityHidden(pending)
            .environment(\.coachmarkReporter, { id, token, frame in
                if targets[id]?[token] != frame {
                    if let frame { targets[id, default: [:]][token] = frame }
                    else { targets[id]?[token] = nil }
                }
            })
            .overlay {
                if pending, tour.steps.indices.contains(currentIndex) {
                    GeometryReader { proxy in
                        let original = tour.steps[currentIndex]
                        let step = original.target == "workout.start" && model.data.activeWorkout != nil
                            ? CoachmarkStep(target: "workout.today", title: "운동이 진행 중이에요", message: "세트를 마칠 때마다 완료를 체크하세요.")
                            : original.target == "workout.start" && model.todayPlan.isRestDay
                            ? CoachmarkStep(target: "workout.start", title: "먼저 운동을 계획해요", message: "계획 탭에서 오늘 할 운동을 추가하세요.")
                            : original
                        CoachmarkOverlay(step: step, index: currentIndex, count: tour.steps.count,
                                         target: (targets[step.target]?.values.first).map {
                                             $0.offsetBy(dx: -proxy.frame(in: .global).minX, dy: -proxy.frame(in: .global).minY)
                                         }, size: proxy.size,
                                         accent: tour.id.hasPrefix("daily.") ? .teal : .orange) {
                            if currentIndex + 1 == tour.steps.count {
                                if model.replayingCoachmarks {
                                    model.replayCompletedCoachmarks.insert(tour.id)
                                } else {
                                    _ = model.saveEdit { data in
                                        if !data.completedCoachmarks.contains(tour.id) { data.completedCoachmarks.append(tour.id) }
                                    }
                                }
                            } else {
                                index = currentIndex + 1
                                progressID = tour.id
                            }
                        }
                        .id("\(tour.id).\(currentIndex)")
                    }
                }
            }
            .onChange(of: tour.id) { _, _ in progressID = tour.id; index = 0 }
            .onChange(of: model.selection.generation) { _, _ in progressID = ""; index = 0 }
            .onChange(of: model.coachmarkReplayGeneration) { _, _ in progressID = ""; index = 0 }
    }
}

/// One measured target and a non-overlapping explanation, in the overlay's coordinate space.
struct CoachmarkPlacement {
    let highlight: CGRect
    let card: CGRect
    let below: Bool
    let showsHighlight: Bool

    init(target: CGRect?, size: CGSize, cardHeight: CGFloat) {
        let bounds = CGRect(x: 8, y: 8, width: max(0, size.width - 16), height: max(0, size.height - 16))
        highlight = target.map { $0.insetBy(dx: -6, dy: -6).intersection(bounds) } ?? .null
        let hasTarget = !highlight.isNull && !highlight.isEmpty
        below = hasTarget && size.height - highlight.maxY - 40 >= cardHeight
        let above = hasTarget && !below && highlight.minY - 40 >= cardHeight
        showsHighlight = below || above
        let proposedTop = below ? highlight.maxY + 28 : above ? highlight.minY - cardHeight - 28 : size.height - cardHeight - 16
        let top = max(8, min(max(8, size.height - cardHeight - 8), proposedTop))
        let width = min(460, max(0, size.width - 32))
        let centerX = showsHighlight
            ? min(max(16 + width / 2, highlight.midX), size.width - 16 - width / 2)
            : size.width / 2
        card = CGRect(x: centerX - width / 2, y: top, width: width, height: cardHeight)
    }
}

private struct CoachmarkOverlay: View {
    let step: CoachmarkStep
    let index: Int
    let count: Int
    let target: CGRect?
    let size: CGSize
    let accent: Color
    let advance: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var headingFocused: Bool
    @State private var cardHeight: CGFloat = 210
    @State private var explanationHeight: CGFloat = 80
    @Environment(\.coachmarkCardObserver) private var observeCard
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var revealed = false
    @State private var pulse = false

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(step.title).font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
            Text(step.message).font(.body).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepCounter: some View {
        Text("\(index + 1) / \(count)").font(.subheadline).foregroundStyle(.secondary)
            .monospacedDigit().lineLimit(1)
            .accessibilityLabel("전체 \(count)단계 중 \(index + 1)단계")
    }

    private var nextButton: some View {
        Button(index + 1 == count ? "시작하기" : "다음", action: advance)
            .font(.headline).foregroundStyle(.black)
            .frame(minWidth: 104, minHeight: 52)
            .frame(maxWidth: textSize.isAccessibilitySize ? .infinity : nil)
            .background(accent, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("coachmark.next")
    }

    var body: some View {
        let placement = CoachmarkPlacement(target: target, size: size, cardHeight: cardHeight)
        let visible = placement.highlight
        let spotlight = placement.showsHighlight
        ZStack(alignment: .top) {
            Rectangle().fill(.black.opacity(0.7))
                .mask {
                    Canvas { context, canvasSize in
                        context.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(.white))
                        if spotlight {
                            context.blendMode = .destinationOut
                            context.fill(Path(roundedRect: visible, cornerRadius: 12), with: .color(.white))
                        }
                    }
                }
                .contentShape(Rectangle()).onTapGesture { }
                .accessibilityHidden(true)
            if spotlight {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(accent, lineWidth: pulse ? 4 : 2)
                    .frame(width: visible.width, height: visible.height)
                    .position(x: visible.midX, y: visible.midY)
                    .accessibilityHidden(true)
                Image(systemName: placement.below ? "arrow.up" : "arrow.down")
                    .font(.body.bold()).foregroundStyle(accent)
                    .position(x: min(max(24, visible.midX), size.width - 24),
                              y: placement.below ? visible.maxY + 14 : visible.minY - 14)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 16) {
                ScrollView {
                    explanation
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { explanationHeight = $0 }
                }
                .frame(height: min(explanationHeight, max(44, size.height * 0.32)))
                if textSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        stepCounter
                        nextButton.frame(maxWidth: .infinity)
                    }
                } else {
                    HStack {
                        stepCounter
                        Spacer()
                        nextButton
                    }
                }
            }
            .padding(20)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .frame(width: placement.card.width)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
            .opacity(revealed ? 1 : 0)
            .offset(x: placement.card.midX - size.width / 2,
                    y: placement.card.minY + (revealed || reduceMotion ? 0 : 8))
            .onGeometryChange(for: CoachmarkPresentation.self) { proxy in
                CoachmarkPresentation(card: proxy.frame(in: .global), highlightsTarget: spotlight)
            } action: { observeCard?($0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .task(id: reduceMotion) {
            if reduceMotion {
                pulse = false
                revealed = true
                headingFocused = true
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(100))
                withAnimation(.easeOut(duration: 0.24)) { revealed = true }
                headingFocused = true
                for _ in 0..<2 {
                    withAnimation(.easeInOut(duration: 0.3)) { pulse = true }
                    try await Task.sleep(for: .milliseconds(300))
                    withAnimation(.easeInOut(duration: 0.3)) { pulse = false }
                    try await Task.sleep(for: .milliseconds(300))
                }
            } catch { } // A new step or dismissal cancels the finite attention cue.
        }
    }
}
