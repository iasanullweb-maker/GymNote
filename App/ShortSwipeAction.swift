import SwiftUI

/// 화면/행 너비와 관계없이 일정 거리만 밀면 실행한다.
/// (사용자 요청 2026-10-09: 가로 iPad에서도 짧게 밀어 삭제. 시스템 swipeActions는 전체 밀기 거리를 바꿀 수 없어 직접 구현한다.)
///
/// 모양: 행 내용은 제자리에 두고(어느 운동을 지우는지 읽히도록), 오른쪽에서 둥근 빨간 버튼이 밀린 거리만큼 자라며 내용 위를 덮는다.
/// 행 여백을 이 modifier가 직접 그려서 버튼이 행 높이 전체를 쓰고 목록 여백에 잘리지 않는다.
private struct ShortSwipeAction: ViewModifier {
    @Environment(\.editMode) private var editMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let action: () -> Void
    @State private var revealed: Bool
    @GestureState private var drag: CGFloat = 0

    /// 기본 목록 행 여백(iOS inset grouped 기준). 이 modifier가 listRowInsets를 0으로 바꾸고 대신 그린다.
    static let rowInsets = EdgeInsets(top: 11, leading: 20, bottom: 11, trailing: 20)
    /// 버튼이 열렸을 때 버튼 영역 너비.
    static let revealWidth: CGFloat = 88
    static let maxTravel: CGFloat = 160

    init(title: String, startsRevealed: Bool, action: @escaping () -> Void) {
        self.title = title
        self.action = action
        _revealed = State(initialValue: startsRevealed)
    }

    private var editing: Bool { editMode?.wrappedValue.isEditing == true }
    /// 0(닫힘) ... maxTravel. 양수 = 왼쪽으로 밀린 거리.
    private var travel: CGFloat {
        guard !editing else { return 0 }
        return min(Self.maxTravel, max(0, (revealed ? Self.revealWidth : 0) - drag))
    }

    func body(content: Content) -> some View {
        let travel = travel
        HStack(spacing: 12) {
            if editing {
                Button(role: .destructive, action: perform) {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(title)
            }
            content.frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(!revealed || editing)
        }
        .padding(Self.rowInsets)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(alignment: .trailing) {
            if travel > 0 {
                HStack(spacing: 0) {
                    // 버튼 아래로 들어가는 긴 글자는 잘린 모서리 대신 부드럽게 사라진다.
                    LinearGradient(colors: [Color(.secondarySystemGroupedBackground).opacity(0), Color(.secondarySystemGroupedBackground)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 16)
                        .allowsHitTesting(false)
                    deleteButton(width: travel)
                        .background(Color(.secondarySystemGroupedBackground))
                }
                .transition(.opacity)
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .listRowInsets(EdgeInsets())
        .simultaneousGesture(
            DragGesture(minimumDistance: 16)
                .updating($drag) { value, state, _ in
                    if abs(value.translation.width) > abs(value.translation.height) {
                        state = value.translation.width
                    }
                }
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    // 120pt 왼쪽 이동으로 바로 실행. 예측 속도·화면 폭은 임계값에 쓰지 않는다.
                    if value.translation.width <= -120 {
                        perform()
                    } else if value.translation.width <= -36 {
                        revealed = true
                    } else if value.translation.width >= 36 {
                        revealed = false
                    }
                },
            including: editing ? .none : .all
        )
        .simultaneousGesture(TapGesture().onEnded {
            if revealed { revealed = false }
        })
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: revealed)
        .accessibilityAction(named: Text(title)) { perform() }
    }

    /// 밀린 거리만큼 커지는 둥근 빨간 버튼. 행 위아래·오른쪽에 6~8pt 여백을 두어 둥근 목록 모서리에 닿지 않는다.
    private func deleteButton(width: CGFloat) -> some View {
        let buttonWidth = max(0, width - 8)
        return Button(role: .destructive, action: perform) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.red)
                if buttonWidth >= 56 {
                    VStack(spacing: 2) {
                        Image(systemName: "trash")
                        Text(title).font(.caption).lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .fixedSize()
                } else if buttonWidth >= 28 {
                    Image(systemName: "trash").foregroundStyle(.white)
                }
            }
            .frame(width: buttonWidth)
            .frame(maxHeight: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderless)
        .padding(.trailing, 8)
        .accessibilityLabel(title)
    }

    private func perform() {
        revealed = false
        action()
    }
}

extension View {
    /// startsRevealed는 화면 캡처 테스트에서 버튼이 열린 모양을 그리기 위한 값이다. 앱에서는 기본값(false)을 쓴다.
    func shortSwipeAction(_ title: String = "삭제", startsRevealed: Bool = false, action: @escaping () -> Void) -> some View {
        modifier(ShortSwipeAction(title: title, startsRevealed: startsRevealed, action: action))
    }
}
