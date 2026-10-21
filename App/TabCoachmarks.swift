import SwiftUI

struct CoachmarkStep {
    let target: String
    let title: String
    let message: String
}

struct TabCoachTour {
    let id: String
    let steps: [CoachmarkStep]

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
                      message: "−/+ 버튼으로 휴식 시간을 조절하세요.")
            ])
        }
    }
}

/// Only presentation preferences; never stored in the account or shared workout store.
enum CoachmarkHistory {
    static let key = "gymnote.coachmarks.completed.v1"
    static func contains(_ id: String, in value: String) -> Bool {
        value.split(separator: "\n").contains(Substring(id))
    }
    static func completing(_ id: String, in value: String) -> String {
        guard !contains(id, in: value) else { return value }
        return (value.split(separator: "\n").map(String.init) + [id]).joined(separator: "\n")
    }
}

private struct CoachmarkAnchors: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func coachmarkTarget(_ id: String, enabled: Bool = true) -> some View {
        anchorPreference(key: CoachmarkAnchors.self, value: .bounds) { enabled ? [id: $0] : [:] }
    }

    func tabCoachmarks(_ tour: TabCoachTour) -> some View {
        modifier(TabCoachmarkHost(tour: tour))
    }
}

private struct TabCoachmarkHost: ViewModifier {
    let tour: TabCoachTour
    @Environment(AppModel.self) private var model
    @AppStorage(CoachmarkHistory.key) private var completed = ""
    @State private var progressID = ""
    @State private var index = 0

    private var pending: Bool { !CoachmarkHistory.contains(tour.id, in: completed) }
    private var currentIndex: Int { progressID == tour.id ? index : 0 }

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!pending)
            .accessibilityHidden(pending)
            .overlayPreferenceValue(CoachmarkAnchors.self) { anchors in
                if pending, tour.steps.indices.contains(currentIndex) {
                    GeometryReader { proxy in
                        let original = tour.steps[currentIndex]
                        let step = original.target == "workout.start" && model.data.activeWorkout != nil
                            ? CoachmarkStep(target: "workout.today", title: "운동이 진행 중이에요", message: "세트를 마칠 때마다 완료를 체크하세요.")
                            : original.target == "workout.start" && model.todayPlan.isRestDay
                            ? CoachmarkStep(target: "workout.start", title: "먼저 운동을 계획해요", message: "계획 탭에서 오늘 할 운동을 추가하세요.")
                            : original
                        CoachmarkOverlay(step: step, index: currentIndex, count: tour.steps.count,
                                         target: anchors[step.target].map { proxy[$0] }, size: proxy.size,
                                         accent: tour.id.hasPrefix("daily.") ? .teal : .orange) {
                            if currentIndex + 1 == tour.steps.count {
                                completed = CoachmarkHistory.completing(tour.id, in: completed)
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
                ViewThatFits(in: .vertical) {
                    explanation
                    ScrollView { explanation }
                }
                .frame(maxHeight: max(44, size.height * 0.32))
                HStack {
                    Text("\(index + 1) / \(count)").font(.subheadline).foregroundStyle(.secondary)
                        .monospacedDigit()
                        .accessibilityLabel("전체 \(count)단계 중 \(index + 1)단계")
                    Spacer()
                    Button(index + 1 == count ? "시작하기" : "다음", action: advance)
                        .font(.headline).foregroundStyle(.black)
                        .frame(minWidth: 104, minHeight: 52)
                        .background(accent, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("coachmark.next")
                }
            }
            .padding(20)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .frame(width: placement.card.width)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: CoachmarkCardHeight.self, value: proxy.size.height)
                }
            }
            .opacity(revealed ? 1 : 0)
            .offset(x: placement.card.midX - size.width / 2,
                    y: placement.card.minY + (revealed || reduceMotion ? 0 : 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onPreferenceChange(CoachmarkCardHeight.self) { cardHeight = $0 }
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

private struct CoachmarkCardHeight: PreferenceKey {
    static var defaultValue: CGFloat { 210 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
