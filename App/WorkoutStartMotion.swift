import SwiftUI

/// 운동 시작 때 아래 '운동 중' 바가 나타나는 방식. 기기별 설정(설정 → 화면).
/// 2026-10-21 사용자 요청: 기본은 B '버튼이 바로 변신', 실기기에서 보고 A '아래에서 올라오기'로 바꿀 수 있게.
enum WorkoutStartAnimationStyle: String, CaseIterable, Identifiable {
    /// B: 누른 주황 버튼이 아래 바 자리로 날아가며 바 모양으로 바뀐다.
    case morph
    /// A: 바가 화면 아래(탭 막대 뒤)에서 스프링으로 올라온다.
    case rise

    var id: String { rawValue }
    static let storageKey = "workoutStartAnimationStyle"
    static let defaultStyle = WorkoutStartAnimationStyle.morph

    var title: String {
        switch self {
        case .morph: "버튼이 바로 변신"
        case .rise: "아래에서 올라오기"
        }
    }
}

/// 운동 시작 애니메이션의 진행 상태. RootView가 하나 만들고 환경으로 내려준다.
/// 시작 버튼(실행 탭 목록 안)과 운동 중 바(탭 아래 safeAreaInset)는 서로 다른 화면 층이라,
/// 두 위치를 화면(global) 좌표로 받아 맨 위 층(overlay)에 '날아가는 판'을 그린다.
/// (목록 셀은 별도 UIKit 층에 호스팅되므로 이름 붙인 좌표계 대신 global을 쓴다.)
@MainActor @Observable
final class WorkoutStartMotion {
    enum Phase { case idle, waitingForBar, flying }

    /// B 이동: 약간의 튕김으로 '도킹' 느낌.
    static let flight = Animation.spring(duration: 0.5, bounce: 0.12)
    /// A 올라오기, 그리고 두 방식 공통으로 목록 아래 여백이 늘어나는 움직임.
    static let rise = Animation.spring(duration: 0.45, bounce: 0.18)
    /// 끝낼 때는 들어온 길(아래)로, 더 빠르고 튕김 없이.
    static let exit = Animation.spring(duration: 0.3, bounce: 0)
    /// 바 frame이 이 시간 안에 오지 않으면(다른 탭 등) 날지 않고 바를 바로 보인다.
    static let barTimeout: Duration = .milliseconds(800)

    private(set) var phase: Phase = .idle
    /// 실행 탭 시작 버튼의 마지막 위치(global 좌표).
    var startFrame: CGRect?
    private(set) var from: CGRect = .zero
    private(set) var to: CGRect = .zero
    private(set) var progress: Double = 0
    /// 바 테두리를 한 번 반짝이게 하는 신호. 값이 바뀔 때마다 반짝인다.
    private(set) var pulse = 0
    private var fallback: Task<Void, Never>?

    /// 날아가는 동안 진짜 바는 숨긴다(판과 겹쳐 두 개로 보이지 않게).
    var barHidden: Bool { phase != .idle }

    /// B 시작. 시작 버튼 위치를 모르면 false(호출한 쪽이 A처럼 처리).
    @discardableResult
    func beginMorph() -> Bool {
        guard let startFrame, startFrame.width > 1, startFrame.height > 1 else { return false }
        from = startFrame
        to = startFrame
        progress = 0
        phase = .waitingForBar
        fallback?.cancel()
        fallback = Task { [weak self] in
            try? await Task.sleep(for: Self.barTimeout)
            guard !Task.isCancelled, let self, self.phase == .waitingForBar else { return }
            self.land()
        }
        return true
    }

    /// 실행 탭의 운동 중 바가 자리 잡은 위치. 기다리던 중이면 날기 시작한다.
    func barFrameChanged(_ frame: CGRect) {
        guard phase == .waitingForBar, frame.width > 1, frame.height > 1 else { return }
        fallback?.cancel()
        to = frame
        phase = .flying
        withAnimation(Self.flight) {
            progress = 1
        } completion: { [weak self] in
            self?.land()
        }
    }

    /// 판을 거두고 진짜 바를 보인 뒤 테두리를 반짝인다.
    func land() {
        fallback?.cancel()
        guard phase != .idle else { return }
        withAnimation(.easeOut(duration: 0.15)) { phase = .idle }
        pulse += 1
    }

    /// A: 바가 다 올라온 뒤 반짝임.
    func risen() { pulse += 1 }

    /// 운동이 끝나거나 취소되면 진행 중인 애니메이션을 정리한다.
    func reset() {
        fallback?.cancel()
        phase = .idle
        progress = 0
    }
}

private struct WorkoutStartMotionKey: EnvironmentKey {
    static let defaultValue: WorkoutStartMotion? = nil
}

extension EnvironmentValues {
    /// 없으면(테스트·미리보기) 애니메이션 없이 바로 바뀐다.
    var workoutStartMotion: WorkoutStartMotion? {
        get { self[WorkoutStartMotionKey.self] }
        set { self[WorkoutStartMotionKey.self] = newValue }
    }
}

/// B에서 시작 버튼 자리 → 운동 중 바 자리로 날아가는 판. progress 0이면 시작 버튼과 같은 모양, 1이면 바 모양.
struct WorkoutStartFlight: View, Animatable {
    var progress: Double
    let from: CGRect
    let to: CGRect
    /// 이 판을 그리는 overlay의 global 원점. from/to(global)를 overlay 좌표로 옮길 때 뺀다.
    var origin: CGPoint = .zero

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private static func mix(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }

    var body: some View {
        // 스프링 튕김으로 1을 살짝 넘을 수 있다. 위치는 그대로 따르고 모양·색은 0...1로 묶는다.
        let t = progress
        let shape = min(max(progress, 0), 1)
        let width = max(Self.mix(from.width, to.width, t), 1)
        let height = max(Self.mix(from.height, to.height, t), 1)
        let midX = Self.mix(from.midX, to.midX, t)
        let midY = Self.mix(from.midY, to.midY, t)
        let radius = Self.mix(12, 28, shape)
        let orange = max(0, 1 - shape * 1.25)   // 80% 지점에서 주황이 다 빠짐
        let label = max(0, 1 - shape * 2.5)     // 버튼 글자는 처음 40% 안에 사라짐
        let plate = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            plate.fill(.regularMaterial)
            plate.fill(Color.orange).opacity(orange)
            plate.strokeBorder(Color.orange.opacity(0.25 + 0.5 * shape), lineWidth: 1)
            Label("운동 시작", systemImage: "play.fill")
                .font(.headline)
                .foregroundStyle(.black)
                .lineLimit(1)
                .opacity(label)
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.12 * shape), radius: 10, y: 4)
        .position(x: midX - origin.x, y: midY - origin.y)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 시작 버튼을 누르는 동안 살짝(97%) 눌리는 모양.
struct PressScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
