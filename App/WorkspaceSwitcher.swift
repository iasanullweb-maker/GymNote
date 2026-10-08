import SwiftUI

/// 화면 너비를 함께 쓰는 두 개의 큰 선택 버튼.
struct WorkspaceSwitcher: View {
    @Binding var selection: String
    @Environment(\.gymnoteCompactLayout) private var compact
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            workspaceButton("운동", icon: "figure.strengthtraining.traditional", color: .orange)
            workspaceButton("일상", icon: "leaf", color: .teal)
        }
        .padding(5)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: selection)
    }

    private func workspaceButton(_ name: String, icon: String, color: Color) -> some View {
        let selected = selection == name
        return Button { selection = name } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.title2.weight(.semibold))
                Text(name).font(.title3.weight(.semibold))
            }
            .foregroundStyle(selected ? color : Color.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, compact ? 6 : 12)
            .frame(maxWidth: .infinity, minHeight: compact ? 44 : 60)
            .background(selected ? color.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .strokeBorder(selected ? color.opacity(0.6) : Color.clear, lineWidth: 1.5)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(color)
                    .padding(8).opacity(selected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .contentShape(RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityValue(selected ? "선택됨" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#Preview("분야 전환") {
    WorkspaceSwitcherPreview()
}

private struct WorkspaceSwitcherPreview: View {
    @State private var selection = "운동"
    var body: some View {
        VStack(spacing: 24) {
            WorkspaceSwitcher(selection: $selection)
            Text("현재 분야: " + selection)
        }
        .padding(16)
    }
}