import StopNetworking
import StopSession
import SwiftUI

/// Models for SwiftUI previews: in-memory store and network, never the real ones.
@MainActor
enum PreviewData {
    /// An `AppModel` already past launch. With a `playerName` it has a profile; without one it's at onboarding.
    static func model(playerName: String? = "Gui") -> AppModel {
        let arguments = playerName.map { ["-playerName", $0] } ?? []
        let model = AppModel(store: InMemoryGameStore(), factory: InMemoryNetwork(), launchArguments: arguments)
        Task { await model.bootstrap() }
        return model
    }
}
