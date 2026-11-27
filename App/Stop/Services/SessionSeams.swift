import Foundation
import os
import StopCore
import StopNetworking
import StopSession

// App-side seams for the session types: `ClientSession` and `MockGameLauncher` / `BotPlayer` (Task 12).
// `AppModel` only talks to these, so tests can stub them. When `MockGameLauncher` lands, wire it in
// `SessionFactories.live`:
//
//     launchMockGame: { profile, bots, settings, language, clock in
//         let game = MockGameLauncher.launch(hostProfile: profile, botNames: bots, settings: settings,
//                                            language: language, clock: clock)
//         return MockGame(host: game.host, retained: game.bots + [game.network])
//     }

/// A game client that talks to a host over a transport: `ClientSession`'s lifecycle on top of `GameClient`.
@MainActor protocol RemoteGameSession: GameClient {
    func start()
    func suspend()
    func resume()
    func stop()
    /// Stops and forgets the game (active-game reference and drafts) without telling the host.
    func abandon()
}

extension ClientSession: RemoteGameSession {}

/// Mirrors `ClientSession.Target` (which isn't `Equatable`, so tests can't compare it).
enum ClientTarget: Equatable, Sendable {
    case discovered(DiscoveredGame)
    /// Browse until a game with this ID appears.
    case rejoin(gameID: UUID)

    var sessionTarget: ClientSession.Target {
        switch self {
        case .discovered(let game): .discovered(game)
        case .rejoin(let gameID): .rejoin(gameID: gameID)
        }
    }
}

/// A running mock game (`-mockGame`): the host plus whatever must stay alive with it (bots, their network).
struct MockGame {
    let host: HostSession
    let retained: [AnyObject]
}

struct SessionFactories {
    typealias MakeClient = @MainActor (
        _ profile: Profile, _ target: ClientTarget, _ factory: any TransportFactory, _ store: any GameStore,
        _ clock: any Clock<Duration>
    ) -> any RemoteGameSession

    /// Returns a started host whose bots have been told to join.
    typealias LaunchMockGame = @MainActor (
        _ hostProfile: Profile, _ botNames: [String], _ settings: GameSettings, _ language: GameLanguage,
        _ clock: any Clock<Duration>
    ) -> MockGame?

    var makeClient: MakeClient
    var launchMockGame: LaunchMockGame

    /// Production wiring. Until `MockGameLauncher` exists in StopKit, mock mode starts a host without bots.
    static let live = SessionFactories(
        makeClient: { profile, target, factory, store, clock in
            ClientSession(profile: profile, target: target.sessionTarget, factory: factory, store: store, clock: clock)
        },
        launchMockGame: { profile, bots, settings, language, clock in
            hostOnlyMockGame(hostProfile: profile, botNames: bots, settings: settings, language: language, clock: clock)
        })

    /// A host on its own in-memory network, with no bots (stand-in for `MockGameLauncher`).
    @MainActor
    static func hostOnlyMockGame(hostProfile: Profile, botNames: [String], settings: GameSettings,
                                 language: GameLanguage, clock: any Clock<Duration>) -> MockGame? {
        let network = InMemoryNetwork()
        let state: GameState
        do {
            state = try GameEngine.newGame(gameID: UUID(), hostID: hostProfile.playerID, hostName: hostProfile.name,
                                           settings: settings, language: language)
        } catch {
            Logger.app.error("mock game: invalid settings")
            return nil
        }
        let host = HostSession(state: state, factory: network, store: InMemoryGameStore(), clock: clock)
        host.start()
        return MockGame(host: host, retained: [network])
    }
}
