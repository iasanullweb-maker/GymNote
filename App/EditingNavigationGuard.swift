import Observation
import SwiftUI

/// 여러 편집기가 겹쳐 있어도 마지막 편집기가 닫힐 때까지 화면 전환을 막는다.
@Observable
final class EditingNavigationGuard {
    private var editors: Set<UUID> = []

    var isEditing: Bool { !editors.isEmpty }

    func begin(_ editor: UUID) { editors.insert(editor) }
    func end(_ editor: UUID) { editors.remove(editor) }

    func allowsSelection<Value: Equatable>(from current: Value, to next: Value) -> Bool {
        current == next || !isEditing
    }
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
