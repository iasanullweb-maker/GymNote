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
                .init(target: daily ? "daily.today" : "workout.today",
                      title: daily ? "오늘 할 일을 체크해요" : "오늘 운동은 여기서 시작해요",
                      message: daily
                        ? "+ 버튼으로 일상을 추가하고, 항목 왼쪽의 원을 눌러 완료해요. 반복 항목을 길게 누르면 그 날짜만 건너뛸 수 있어요."
                        : "계획한 운동이 있으면 ‘운동 시작’을 누른 뒤 세트를 체크해요. 세트 완료 후 휴식 타이머가 자동으로 시작돼요. 휴식일에는 계획 탭에서 운동을 먼저 추가해 주세요."),
                .init(target: "workspace", title: "운동과 일상을 오가요",
                      message: "위 버튼으로 운동과 일상을 전환해요. 각각의 계획과 기록을 따로 확인할 수 있어요.")
            ])
        case 1:
            var steps = [CoachmarkStep(target: "\(scope).calendar", title: "날짜를 길게 눌러 보세요",
                message: "달력의 날짜를 길게 누르면 그날의 상세 화면이 열려요. 운동 기록이 없는 날은 계획을 설정하고, 운동한 날은 기록을 확인할 수 있어요.")]
            if !daily {
                steps.append(.init(target: "workout.plan", title: "이 버튼으로도 계획을 열어요",
                    message: "달력에서 날짜를 한 번 누른 뒤 ‘선택한 날짜 계획 설정’을 눌러도 돼요. 편집 화면에서 운동을 추가하고, 운동 행을 왼쪽으로 밀어 삭제할 수 있어요."))
            }
            return Self(id: "\(scope).plans", steps: steps)
        case 2:
            return Self(id: "\(scope).records", steps: [
                .init(target: daily ? "daily.history" : "workout.records",
                      title: daily ? "완료한 일상을 돌아봐요" : "일지와 최고 기록을 확인해요",
                      message: daily
                        ? "이번 주 완료 개수와 반복 일정 달성률을 볼 수 있어요. 아래 완료 기록에서 날짜를 열고 항목을 왼쪽으로 밀면 완료를 취소할 수 있어요."
                        : "위에서 운동 일지·친구 순위·최고 기록을 전환해요. 일지 달력의 날짜를 누르면 그날의 일지가 보이고, 길게 누르면 상세 화면이 열려요.")
            ])
        case 3:
            return Self(id: "friends", steps: [
                .init(target: "friends", title: "친구와 함께 운동해요",
                      message: "로그인 후 닉네임을 정하고 친구 코드로 친구를 추가해요. 그룹도 만들 수 있어요. 친구와의 순위는 기록 탭의 ‘친구’에서 확인해요.")
            ])
        default:
            return Self(id: "settings", steps: [
                .init(target: "settings.rest", title: "나에게 맞게 휴식을 설정해요",
                      message: "세트 사이 휴식 시간과 타이머 −/+ 버튼의 조절 간격을 바꿀 수 있어요. 아래에서는 일상 알림과 계정도 관리해요.")
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
    func coachmarkTarget(_ id: String) -> some View {
        anchorPreference(key: CoachmarkAnchors.self, value: .bounds) { [id: $0] }
    }

    func tabCoachmarks(_ tour: TabCoachTour) -> some View {
        modifier(TabCoachmarkHost(tour: tour))
    }
}

private struct TabCoachmarkHost: ViewModifier {
    let tour: TabCoachTour
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
                        let step = tour.steps[currentIndex]
                        // Use measured screen bounds when a lazy row is not present (for example, large text).
                        if let anchor = anchors[step.target] ?? anchors["tour.surface"] {
                            CoachmarkOverlay(step: step, index: currentIndex, count: tour.steps.count,
                                             target: proxy[anchor], size: proxy.size) {
                                if currentIndex + 1 == tour.steps.count {
                                    completed = CoachmarkHistory.completing(tour.id, in: completed)
                                } else {
                                    index = currentIndex + 1
                                    progressID = tour.id
                                }
                            }
                        } else {
                            // Block background interaction while the target is being laid out.
                            Color.black.opacity(0.7).ignoresSafeArea()
                                .overlay { ProgressView("안내를 준비하는 중…").tint(.white).foregroundStyle(.white) }
                        }
                    }
                }
            }
            .onChange(of: tour.id) { _, _ in progressID = tour.id; index = 0 }
    }
}

private struct CoachmarkOverlay: View {
    let step: CoachmarkStep
    let index: Int
    let count: Int
    let target: CGRect
    let size: CGSize
    let advance: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var headingFocused: Bool
    @State private var cardHeight: CGFloat = 240

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(step.title).font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
            Text(step.message).font(.body).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        let cardTop = max(0, size.height - cardHeight - 16)
        let visible = target.insetBy(dx: -4, dy: -4).intersection(
            CGRect(x: 8, y: 4, width: max(0, size.width - 16), height: max(0, cardTop - 40)))
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.black.opacity(0.7))
                .mask {
                    Canvas { context, canvasSize in
                        context.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(.white))
                        if !visible.isNull, !visible.isEmpty {
                            context.blendMode = .destinationOut
                            context.fill(Path(roundedRect: visible, cornerRadius: 12), with: .color(.white))
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { }
                .accessibilityHidden(true)
            if !visible.isNull, !visible.isEmpty {
                Image(systemName: "arrow.up")
                    .font(.title2.bold()).foregroundStyle(.white)
                    .position(x: visible.midX, y: visible.maxY + 20)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .vertical) {
                    explanation
                    ScrollView { explanation }
                }
                .frame(maxHeight: size.height * 0.32)
                HStack {
                    Text("\(index + 1) / \(count)").font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityLabel("전체 \(count)단계 중 \(index + 1)단계")
                    Spacer()
                    Button(index + 1 == count ? "완료" : "다음", action: advance)
                        .font(.headline).foregroundStyle(.primary)
                        .frame(minWidth: 88, minHeight: 52)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("coachmark.next")
                }
            }
            .padding(20)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: 460)
            .padding(.horizontal, 16).padding(.bottom, 16)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: CoachmarkCardHeight.self, value: proxy.size.height)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onPreferenceChange(CoachmarkCardHeight.self) { cardHeight = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .task(id: index) { headingFocused = true }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: index)
    }
}

private struct CoachmarkCardHeight: PreferenceKey {
    static var defaultValue: CGFloat { 240 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
