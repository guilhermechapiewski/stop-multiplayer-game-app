import Foundation
import Observation
import os
import StopCore
import StopNetworking
import StopSession
import SwiftUI

/// App-wide state: the profile, which screen is showing, and the game session in progress (if any).
@MainActor @Observable
final class AppModel {
    enum Route: Equatable {
        case loading, onboarding, home, hostSetup, join, practiceSetup, rejoining(ActiveGameRef), game
    }

    private(set) var route: Route = .loading
    private(set) var profile: Profile?
    /// The session the game screens read from: the host's `LocalGameClient` or a remote session.
    private(set) var client: (any GameClient)?

    /// `-uiTesting`: clean state, no sounds, forced Reduce Motion.
    let isUITesting: Bool
    /// Sounds play only if the player wants them and we're not under UI test.
    var soundsEnabled: Bool { !isUITesting && (profile?.soundsEnabled ?? true) }

    /// Bots in `-mockGame` mode.
    static let mockBotNames = ["Ana", "Bia", "Caio"]

    @ObservationIgnored private let store: any GameStore
    @ObservationIgnored private let factory: any TransportFactory
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let sessions: SessionFactories
    @ObservationIgnored private let launch: LaunchOptions

    @ObservationIgnored private var hostSession: HostSession?
    @ObservationIgnored private var remoteSession: (any RemoteGameSession)?
    @ObservationIgnored private var retained: [AnyObject] = []
    @ObservationIgnored private var sessionWatch: Task<Void, Never>?

    init(store: any GameStore, factory: any TransportFactory, clock: any Clock<Duration> = ContinuousClock(),
         launchArguments: [String] = ProcessInfo.processInfo.arguments, sessions: SessionFactories = .live) {
        self.store = store
        self.factory = factory
        self.clock = clock
        self.sessions = sessions
        launch = LaunchOptions(arguments: launchArguments)
        isUITesting = launch.uiTesting
    }

    /// The language new games use: the app's UI language.
    var gameLanguage: GameLanguage {
        Bundle.main.preferredLocalizations.first?.hasPrefix("pt") == true ? .ptBR : .en
    }

    // MARK: Launch

    /// Loads the profile, then resumes an interrupted game if there is one; otherwise Home or onboarding.
    func bootstrap() async {
        guard route == .loading else { return }
        if let name = launch.playerName {
            await saveProfile(name: name)
        } else {
            profile = await store.loadProfile()
        }
        guard profile != nil else {
            route = .onboarding
            return
        }
        if launch.mockGame {
            startMockGame()
        } else if let ref = await store.loadActiveGame() {
            await restore(ref)
        } else {
            route = .home
        }
    }

    private func restore(_ ref: ActiveGameRef) async {
        guard let profile else { return }
        switch ref.role {
        case .host:
            guard let saved = await store.loadHostGame(), saved.gameID == ref.gameID,
                  saved.hostID == profile.playerID, saved.phase != .gameOver else {
                await store.saveActiveGame(nil)
                await store.saveHostGame(nil)
                route = .home
                return
            }
            startHost(HostSession(state: saved, factory: factory, store: store, clock: clock))
        case .client:
            startClient(target: .rejoin(gameID: ref.gameID), route: .rejoining(ref))
        }
    }

    // MARK: Profile

    /// Trims `name`; blank names are ignored. Creates the profile (with a fresh player ID) on first use.
    func saveName(_ name: String) async {
        guard await saveProfile(name: name) else { return }
        if route == .onboarding {
            if launch.mockGame { startMockGame() } else { route = .home }
        }
    }

    func setSoundsEnabled(_ enabled: Bool) async {
        guard var updated = profile else { return }
        updated.soundsEnabled = enabled
        profile = updated
        await store.saveProfile(updated)
    }

    @discardableResult
    private func saveProfile(name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let existing = await store.loadProfile()
        var updated = existing ?? Profile(playerID: UUID(), name: trimmed, soundsEnabled: true)
        updated.name = trimmed
        profile = updated
        if updated != existing { await store.saveProfile(updated) }
        return true
    }

    // MARK: Navigation

    /// Moves between Home and the screens reachable from it; other routes are entered by the actions below.
    func navigate(to destination: Route) {
        switch destination {
        case .home, .hostSetup, .join, .practiceSetup:
            guard client == nil, profile != nil else { return }
            route = destination
        case .loading, .onboarding, .rejoining, .game:
            return
        }
    }

    // MARK: Games

    func hostGame(settings: GameSettings) {
        guard let profile, client == nil else { return }
        do {
            let state = try GameEngine.newGame(gameID: UUID(), hostID: profile.playerID, hostName: profile.name,
                                               settings: settings, language: gameLanguage)
            startHost(HostSession(state: state, factory: factory, store: store, clock: clock))
        } catch {
            Logger.app.error("hostGame: invalid settings")
        }
    }

    func join(_ game: DiscoveredGame) {
        guard client == nil else { return }
        startClient(target: .discovered(game), route: .game)
    }

    /// Gives up reconnecting to an interrupted game and forgets it.
    func cancelRejoin() {
        guard case .rejoining(let ref) = route else { return }
        remoteSession?.stop()
        endSession()
        Task { [store] in
            await store.saveActiveGame(nil)
            await store.clearDrafts(gameID: ref.gameID)
        }
    }

    /// Leaves the game for good. As host this ends the game for everyone.
    func leaveGame() {
        guard let client else { return }
        client.leave()
        // `leave()` ends the game through the engine; shutting down directly also covers a rejected end.
        hostSession?.shutdown()
        endSession()
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            hostSession?.suspend()
            remoteSession?.suspend()
        case .active:
            hostSession?.resume()
            remoteSession?.resume()
        default:
            break
        }
    }

    // MARK: Sessions

    private func startMockGame() {
        guard let profile else { return }
        let settings = GameSettings(categories: DefaultCategories.list(for: gameLanguage), stopsRequired: 1,
                                    allowGiveUp: true)
        guard let game = sessions.launchMockGame(profile, Self.mockBotNames, settings, gameLanguage, clock) else {
            route = .home
            return
        }
        retained = game.retained
        hostSession = game.host
        client = game.host.localClient
        route = .game
    }

    private func startHost(_ host: HostSession) {
        hostSession = host
        host.start()
        client = host.localClient
        route = .game
    }

    private func startClient(target: ClientTarget, route destination: Route) {
        guard let profile else { return }
        let session = sessions.makeClient(profile, target, factory, store, clock)
        remoteSession = session
        client = session
        route = destination
        session.start()
        watch(session)
    }

    /// While rejoining, moves to the game once state arrives; an ended session returns to Home.
    private func watch(_ session: any RemoteGameSession) {
        sessionWatch?.cancel()
        sessionWatch = Task { [weak self, weak session] in
            let changes = Observations { () -> (hasState: Bool, ended: Bool)? in
                guard let session else { return nil }
                if case .ended = session.hostStatus { return (session.state != nil, true) }
                return (session.state != nil, false)
            }
            for await change in changes {
                guard let self, let change, self.remoteSession === session else { return }
                if case .rejoining = self.route {
                    if change.ended {
                        self.endSession()
                        return
                    }
                    if change.hasState { self.route = .game }
                }
            }
        }
    }

    private func endSession() {
        sessionWatch?.cancel()
        sessionWatch = nil
        hostSession = nil
        remoteSession = nil
        retained = []
        client = nil
        route = .home
    }
}

/// Launch arguments the app understands (all optional).
struct LaunchOptions: Equatable {
    /// `-uiTesting`: wipe the store, no sounds, forced Reduce Motion.
    var uiTesting = false
    /// `-resetState`: wipe the store.
    var resetState = false
    /// `-mockGame`: start hosting straight away with bots on an in-memory network.
    var mockGame = false
    /// `-playerName <name>`: use this name and skip onboarding.
    var playerName: String?

    init(arguments: [String]) {
        uiTesting = arguments.contains("-uiTesting")
        resetState = arguments.contains("-resetState")
        mockGame = arguments.contains("-mockGame")
        if let index = arguments.firstIndex(of: "-playerName"), arguments.indices.contains(index + 1) {
            playerName = arguments[index + 1]
        }
    }

    /// Whether the persisted store must be wiped before it's opened.
    var wipesStore: Bool { uiTesting || resetState }
}
