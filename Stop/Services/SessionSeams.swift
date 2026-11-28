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
    /// The browser was refused local network access (the UI points to Settings).
    var isLocalNetworkDenied: Bool { get }
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
    /// Suspends and resumes the bots with the host (scene phase), so they don't drop and redial the host.
    var suspendBots: @MainActor () -> Void = {}
    var resumeBots: @MainActor () -> Void = {}
}

struct SessionFactories {
    typealias MakeClient = @MainActor (
        _ profile: Profile, _ target: ClientTarget, _ factory: any TransportFactory, _ store: any GameStore,
        _ clock: any Clock<Duration>
    ) -> any RemoteGameSession

    /// `-mockGame` only: returns a started host whose bots have been told to join. The game is saved in `store`
    /// like a hosted one, so a relaunch restores it; `seed` makes it repeatable. Practice games launch with
    /// their own behavior (`BotPlayer.Behavior.practice(speed)`), not through this.
    typealias LaunchMockGame = @MainActor (
        _ hostProfile: Profile, _ botNames: [String], _ settings: GameSettings, _ language: GameLanguage,
        _ seed: UInt64?, _ store: any GameStore, _ clock: any Clock<Duration>
    ) -> MockGame?

    #if DEBUG
    /// Debug builds only. Returns a started practice host on its own in-memory network (never the app's transport), whose bots
    /// have been told to join. `store` only lends the profile and custom categories: the game isn't persisted.
    typealias LaunchPractice = @MainActor (
        _ hostProfile: Profile, _ botNames: [String], _ settings: GameSettings, _ language: GameLanguage,
        _ speed: BotSpeed, _ store: any GameStore, _ clock: any Clock<Duration>
    ) -> MockGame?
    #endif

    var makeClient: MakeClient
    var launchMockGame: LaunchMockGame
    #if DEBUG
    var launchPractice: LaunchPractice
    #endif

    /// Production wiring. Mock mode's bots play for real, and each waits for someone else's STOP before stopping
    /// so the local player always gets to write. Practice bots (Debug builds only) play at the chosen speed.
    static let live: SessionFactories = {
        #if DEBUG
        SessionFactories(makeClient: liveMakeClient, launchMockGame: liveLaunchMockGame,
                         launchPractice: liveLaunchPractice)
        #else
        SessionFactories(makeClient: liveMakeClient, launchMockGame: liveLaunchMockGame)
        #endif
    }()

    private static let liveMakeClient: MakeClient = { profile, target, factory, store, clock in
        ClientSession(profile: profile, target: target.sessionTarget, factory: factory, store: store, clock: clock)
    }

    private static let liveLaunchMockGame: LaunchMockGame = { profile, bots, settings, language, seed, store, clock in
        let game = MockGameLauncher.launch(hostProfile: profile, botNames: bots, settings: settings,
                                           language: language, practice: false,
                                           botBehavior: mockGameBotBehavior(seeded: seed != nil), seed: seed,
                                           store: store, clock: clock)
        return MockGame(bots: game.bots, host: game.host, network: game.network)
    }

    #if DEBUG
    private static let liveLaunchPractice: LaunchPractice = { profile, bots, settings, language, speed, store, clock in
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
        return MockGame(bots: game.bots, host: game.host, network: game.network)
    }
    #endif

    /// `-mockGame` bots (screenshots, UI tests, development): normal speed, and each waits for someone else's
    /// STOP before stopping, so the local player always gets to write. Seeded games (screenshots) have every
    /// answer typed within a few seconds, so the scoring shots show them all. Not for practice games.
    static func mockGameBotBehavior(seeded: Bool) -> BotPlayer.Behavior {
        var behavior = BotPlayer.Behavior.practice(.normal)
        if seeded {
            behavior.stopAfter = .seconds(4)
            // One after another (Ana, then Bia 5 s later, then Caio): the scoring screenshot catches Ana's and
            // Bia's answers revealed and Caio's still hidden, in read-aloud mode. (3 s was too tight a window
            // for the shot on a slower simulator.)
            behavior.scoreStagger = .seconds(5)
        }
        behavior.stopWhenOthersStopped = true
        return behavior
    }
}

extension MockGame {
    /// A host and its bots on their own network: stopping, suspending and resuming reach every bot.
    @MainActor
    init(bots: [BotPlayer], host: HostSession, network: AnyObject) {
        self.init(host: host, retained: bots + [network]) { stop(bots) }
        suspendBots = { for bot in bots { bot.client.suspend() } }
        resumeBots = { for bot in bots { bot.client.resume() } }
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
