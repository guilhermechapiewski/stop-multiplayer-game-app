import UIKit

/// Keeps the screen awake during a game, so a phone left on the table doesn't lock mid-round.
@MainActor
enum IdleTimer {
    static func setDisabled(_ disabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = disabled
    }
}
