import SwiftUI

/// 화면/행 너비와 관계없이 일정 거리만 밀면 실행한다.
private struct ShortSwipeAction: ViewModifier {
    @Environment(\.editMode) private var editMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let action: () -> Void
    @State private var revealed = false
    @GestureState private var drag: CGFloat = 0

    private var editing: Bool { editMode?.wrappedValue.isEditing == true }
    private var offset: CGFloat { min(0, max(-160, (revealed ? -80 : 0) + drag)) }

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            if !editing && offset < 0 {
                Button(role: .destructive, action: perform) {
                    VStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text(title).font(.caption)
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 12)
                    .frame(width: 80)
                    .background(Color.red)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(title)
            }
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
            .background(Color(.secondarySystemGroupedBackground))
            .offset(x: editing ? 0 : offset)
        }
        .clipped()
        .contentShape(Rectangle())
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: revealed)
        .accessibilityAction(named: Text(title)) { perform() }
    }

    private func perform() {
        revealed = false
        action()
    }
}

extension View {
    func shortSwipeAction(_ title: String = "삭제", action: @escaping () -> Void) -> some View {
        modifier(ShortSwipeAction(title: title, action: action))
    }
}
