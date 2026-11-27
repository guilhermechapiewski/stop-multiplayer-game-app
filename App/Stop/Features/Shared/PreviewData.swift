import Foundation
import Observation
import StopCore
import StopNetworking
import StopSession
import SwiftUI

/// Models for SwiftUI previews (and the DEBUG `-demoGames` launch): in-memory store and network, never the
/// real ones.
@MainActor
enum PreviewData {
    /// An `AppModel` already past launch. With a `playerName` it has a profile; without one it's at onboarding.
    static func model(playerName: String? = "Gui") -> AppModel {
        let arguments = playerName.map { ["-playerName", $0] } ?? []
        let model = AppModel(store: InMemoryGameStore(), factory: InMemoryNetwork(), launchArguments: arguments)
        Task { await model.bootstrap() }
        return model
    }

    static let hostID = UUID()
    static let guestID = UUID()

    /// A game client showing a lobby (or `phase`; nil means "still connecting"): Gui hosting, joined by
    /// `playerNames` (two of them called Ana, one of whom is away).
    static func client(isHost: Bool, phase: Phase? = .lobby,
                       playerNames: [String] = ["Ana", "Bia", "Ana", "Caio"]) -> PreviewGameClient {
        var state = try! GameEngine.newGame(
            gameID: UUID(), hostID: hostID, hostName: "Gui",
            settings: GameSettings(categories: Array(DefaultCategories.list(for: .en).prefix(6)), stopsRequired: 2,
                                   allowGiveUp: false),
            language: .en)
        for (index, name) in playerNames.enumerated() {
            let id = index == 0 ? guestID : UUID()
            state.players.append(Player(id: id, name: name, presence: index == 2 ? .away : .present))
        }
        if let phase {
            state.phase = phase
            if phase != .lobby {
                state.rounds = [Round(number: 1, letter: "B", participants: state.players.map(\.id))]
            }
        }
        return PreviewGameClient(localPlayerID: isHost ? hostID : guestID, isHost: isHost,
                                 state: phase == nil ? nil : state)
    }

    #if DEBUG
    /// Games advertised on an in-memory network: one open, one in progress, one from another app version.
    /// Keep the result alive for as long as the games should stay visible.
    static func demoNetwork() -> DemoNetwork {
        let network = InMemoryNetwork()
        let games = [("Ana", 3, currentProtocolVersion, true), ("Bia", 5, currentProtocolVersion, false),
                     ("Caio", 2, currentProtocolVersion + 1, true)]
        let listeners = games.map { host, players, version, joinable in
            let listener = network.makeListener()
            _ = listener.start(advertising: Advertisement(gameID: UUID(), hostName: host, playerCount: players,
                                                          protocolVersion: version, joinable: joinable))
            return listener
        }
        return DemoNetwork(network: network, listeners: listeners)
    }

    static func startedJoinModel(_ network: InMemoryNetwork) -> JoinModel {
        let model = JoinModel(factory: network)
        model.start()
        return model
    }
    #endif
}

#if DEBUG
/// An in-memory network and the listeners advertising on it.
struct DemoNetwork {
    let network: InMemoryNetwork
    let listeners: [any Listener]
}
#endif

/// A `GameClient` with fixed state, for previews. Intents are applied locally where that's simple.
@MainActor @Observable
final class PreviewGameClient: GameClient {
    let localPlayerID: PlayerID
    let isHost: Bool
    var state: GameState?
    var hostStatus: HostStatus = .connected
    let presenceChanges = AsyncStream<PresenceChange> { $0.finish() }
    var lastError: GameError?
    var frozenAnswers: [String]?

    init(localPlayerID: PlayerID, isHost: Bool, state: GameState?) {
        self.localPlayerID = localPlayerID
        self.isHost = isHost
        self.state = state
        if state == nil { hostStatus = .connecting }
    }

    func send(_ intent: Intent) {
        switch intent {
        case .updateRoundSettings(let stops, let allowGiveUp):
            state?.settings.stopsRequired = stops
            state?.settings.allowGiveUp = allowGiveUp
        case .removePlayer(let id):
            if let index = state?.players.firstIndex(where: { $0.id == id }) {
                state?.players[index].presence = .removed
            }
        default:
            break
        }
    }

    func saveDraft(_ answers: [String]) {}
    func draft() async -> [String]? { nil }
    func leave() {}
}
