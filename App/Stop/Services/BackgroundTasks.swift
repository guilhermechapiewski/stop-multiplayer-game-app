import UIKit

/// Asks iOS for a little time in the background (to tell the others we're going away and save the game).
struct BackgroundTasks {
    /// Begins background time named `name`; call the returned function once the work is done.
    var begin: @MainActor (_ name: String) -> @MainActor () -> Void

    static let live = BackgroundTasks { name in
        let handle = BackgroundTaskHandle()
        handle.identifier = UIApplication.shared.beginBackgroundTask(withName: name) {
            // Out of time: end it now (ending twice is harmless).
            MainActor.assumeIsolated { handle.end() }
        }
        return handle.end
    }
}

@MainActor
private final class BackgroundTaskHandle {
    var identifier = UIBackgroundTaskIdentifier.invalid

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
