import Foundation
import os
import StopCore
import StopNetworking
import StopSession
import StopSimulation

// App-side seams for the session types: `ClientSession`, the `-mockGame` host and `MockGameLauncher` (practice).
// `AppModel` only talks to these, so tests can stub them.

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

/// A running game against bots (`-mockGame` or practice): the host plus whatever must stay alive with it (bots,
/// their network).
struct MockGame {
    let host: HostSession
    let retained: [AnyObject]
    /// Stops the bots when the game is closed.
    var stopBots: @MainActor () -> Void = {}
}

struct SessionFactories {
    typealias MakeClient = @MainActor (
        _ profile: Profile, _ target: ClientTarget, _ factory: any TransportFactory, _ store: any GameStore,
        _ clock: any Clock<Duration>
    ) -> any RemoteGameSession

    /// `-mockGame` only: returns a started host whose bots have been told to join. Practice games launch with
    /// their own behavior (`BotPlayer.Behavior.practice(speed)`), not through this.
    typealias LaunchMockGame = @MainActor (
        _ hostProfile: Profile, _ botNames: [String], _ settings: GameSettings, _ language: GameLanguage,
        _ clock: any Clock<Duration>
    ) -> MockGame?

    /// Returns a started practice host on its own in-memory network (never the app's transport), whose bots
    /// have been told to join. `store` only lends the profile and custom categories: the game isn't persisted.
    typealias LaunchPractice = @MainActor (
        _ hostProfile: Profile, _ botNames: [String], _ settings: GameSettings, _ language: GameLanguage,
        _ speed: BotSpeed, _ store: any GameStore, _ clock: any Clock<Duration>
    ) -> MockGame?

    var makeClient: MakeClient
    var launchMockGame: LaunchMockGame
    var launchPractice: LaunchPractice

    /// Production wiring. Mock mode's bots play for real, and each waits for someone else's STOP before stopping
    /// so the local player always gets to write. Practice bots play at the chosen speed.
    static let live = SessionFactories(
        makeClient: { profile, target, factory, store, clock in
            ClientSession(profile: profile, target: target.sessionTarget, factory: factory, store: store, clock: clock)
        },
        launchMockGame: { profile, bots, settings, language, clock in
            let game = MockGameLauncher.launch(hostProfile: profile, botNames: bots, settings: settings,
                                               language: language, botBehavior: mockGameBotBehavior, clock: clock)
            return MockGame(host: game.host, retained: game.bots + [game.network]) { stop(game.bots) }
        },
        launchPractice: { profile, bots, settings, language, speed, store, clock in
            // `MockGameLauncher.launch` has a precondition that the settings are valid (it traps otherwise). The
            // setup screen never offers invalid ones, but a trap would kill the app, so check first and refuse.
            guard (try? GameEngine.newGame(gameID: UUID(), hostID: profile.playerID, hostName: profile.name,
                                           settings: settings, language: language)) != nil else {
                Logger.app.error("practice: invalid settings")
                return nil
            }
            let game = MockGameLauncher.launch(hostProfile: profile, botNames: bots, settings: settings,
                                               language: language, botSpeed: speed, practice: true, store: store,
                                               clock: clock)
            return MockGame(host: game.host, retained: game.bots + [game.network]) { stop(game.bots) }
        })

    /// `-mockGame` bots (screenshots, UI tests, development): normal speed, and each waits for someone else's
    /// STOP before stopping, so the local player always gets to write. Not for practice games.
    static var mockGameBotBehavior: BotPlayer.Behavior {
        var behavior = BotPlayer.Behavior.practice(.normal)
        behavior.stopWhenOthersStopped = true
        return behavior
    }
}

/// Stops bots for good: they stop playing and drop the game (their in-memory store forgets it).
@MainActor
private func stop(_ bots: [BotPlayer]) {
    for bot in bots {
        bot.cancel()
        bot.client.abandon()
    }
}
