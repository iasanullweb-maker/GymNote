import Observation
import SwiftUI

/// 여러 편집기가 겹쳐 있어도 마지막 편집기가 닫힐 때까지 화면 전환을 막는다.
@Observable
final class EditingNavigationGuard {
    private var editors: Set<UUID> = []

    var isEditing: Bool { !editors.isEmpty }

    func begin(_ editor: UUID) { editors.insert(editor) }
    func end(_ editor: UUID) { editors.remove(editor) }

    /// 편집기를 담은 화면 전체가 교체될 때(계정 전환, 로그인 화면 전환) 남은 잠금을 정리한다.
    /// onDisappear가 누락되어도 탭 이동이 계속 막히지 않게 하는 안전장치다.
    func reset() { editors.removeAll() }

    func allowsSelection<Value: Equatable>(from current: Value, to next: Value) -> Bool {
        current == next || !isEditing
    }

    /// 화면 밖(알림 탭 등)에서 들어온 분야 이동 요청을 처리한다.
    /// 편집 중이면 입력 중인 내용을 지키기 위해 이동하지 않고 요청을 버린다.
    func resolvePendingWorkspace(_ pending: String?, current: String) -> String? {
        guard let pending, allowsSelection(from: current, to: pending) else { return nil }
        return pending
    }
}

extension EditingNavigationGuard {
    /// 알림을 눌러 일상 화면으로 열 때 쓰는 대기 요청 키. 화면이 편집 중인지 확인한 뒤 적용한다.
    static let pendingWorkspaceKey = "pendingWorkspace"
}

private struct EditingNavigationGuardKey: EnvironmentKey {
    static let defaultValue: EditingNavigationGuard? = nil
}

extension EnvironmentValues {
    var editingNavigationGuard: EditingNavigationGuard? {
        get { self[EditingNavigationGuardKey.self] }
        set { self[EditingNavigationGuardKey.self] = newValue }
    }
}

private struct EditingNavigationProtection: ViewModifier {
    @Environment(\.editingNavigationGuard) private var navigationGuard
    @State private var editorID = UUID()

    func body(content: Content) -> some View {
        content
            .interactiveDismissDisabled()
            .onAppear { navigationGuard?.begin(editorID) }
            .onDisappear { navigationGuard?.end(editorID) }
    }
}

extension View {
    func protectEditingNavigation() -> some View {
        modifier(EditingNavigationProtection())
    }
}
