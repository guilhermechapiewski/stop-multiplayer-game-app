import SwiftUI

extension EnvironmentValues {
    /// Whether to replace motion with fades or nothing. Views read this instead of
    /// `accessibilityReduceMotion`: it mirrors the system setting, and is forced on under `-uiTesting`
    /// so UI tests never wait on looping animations.
    @Entry var reduceMotion = false
}

extension View {
    /// Sets `\.reduceMotion` for this hierarchy from the system setting, or `true` when `forced`.
    func reduceMotion(forced: Bool) -> some View {
        modifier(ReduceMotionBridge(forced: forced))
    }
}

private struct ReduceMotionBridge: ViewModifier {
    let forced: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    func body(content: Content) -> some View {
        content.environment(\.reduceMotion, forced || systemReduceMotion)
    }
}
