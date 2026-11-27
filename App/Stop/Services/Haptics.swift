import UIKit

/// Haptics for the round's big moments. Each call re-arms its generator with `prepare()`, so the Taptic
/// Engine is awake for the next one (an idle engine adds a noticeable delay).
@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    /// The round's letter lands; writing starts.
    static func letterLanded() { medium.impactOccurred(); medium.prepare() }
    /// A countdown second; a scoring category completes.
    static func tick() { light.impactOccurred(); light.prepare() }
    /// STOP tapped, or the round locks.
    static func stop() { heavy.impactOccurred(); heavy.prepare() }
    /// A score picked.
    static func select() { selection.selectionChanged(); selection.prepare() }
    /// The local player won.
    static func success() { notification.notificationOccurred(.success); notification.prepare() }
}
