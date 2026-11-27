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
    /// Remote sessions saying goodbye to their host; kept alive until they end.
    @ObservationIgnored private var departing: [any RemoteGameSession] = []
    @ObservationIgnored private var profileWrites: Task<Void, Never>?
    @ObservationIgnored private var wasBackgrounded = false

    init(store: any GameStore, factory: any TransportFactory, clock: any Clock<Duration> = ContinuousClock(),
         launchArguments: [String] = ProcessInfo.processInfo.arguments, sessions: SessionFactories = .live) {
        self.store = store
        self.factory = factory
        self.clock = clock
        self.sessions = sessions
        launch = LaunchOptions(arguments: launchArguments)
        isUITesting = launch.uiTesting
    }

    /// The language new games use (it picks the default categories): the device's language.
    var gameLanguage: GameLanguage { Self.language(for: .current) }

    static func language(for locale: Locale) -> GameLanguage {
        locale.language.languageCode == "pt" ? .ptBR : .en
    }

    /// Options for a new hosted game, with this device's custom categories.
    func makeSetupModel() -> HostSetupModel { HostSetupModel(store: store, language: gameLanguage) }

    /// Browses this app's transport for nearby games.
    func makeJoinModel() -> JoinModel { JoinModel(factory: factory) }

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
            if let destination = launch.openRoute { navigate(to: destination) }
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

    /// Takes effect at once; the write to the store follows.
    func setSoundsEnabled(_ enabled: Bool) {
        guard var updated = profile, updated.soundsEnabled != enabled else { return }
        updated.soundsEnabled = enabled
        profile = updated
        enqueueProfileWrite { [weak self] in
            guard let self, let profile = self.profile else { return }
            await self.store.saveProfile(profile)
        }
    }

    @discardableResult
    private func saveProfile(name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        await enqueueProfileWrite { [weak self] in
            guard let self else { return }
            let existing: Profile? = if let profile = self.profile { profile } else { await self.store.loadProfile() }
            var updated = existing ?? Profile(playerID: UUID(), name: trimmed, soundsEnabled: true)
            updated.name = trimmed
            self.profile = updated
            if updated != existing { await self.store.saveProfile(updated) }
        }.value
        return true
    }

    /// Profile writes run one at a time, in order: two quick saves (a double tap, Settings' several commit
    /// points) can't both create a profile or land out of order.
    @discardableResult
    private func enqueueProfileWrite(_ write: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = profileWrites
        let task = Task { @MainActor in
            await previous?.value
            await write()
        }
        profileWrites = task
        return task
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
            Logger.app.error("hostGame: \(String(describing: error), privacy: .public)")
        }
    }

    func join(_ game: DiscoveredGame) {
        guard client == nil else { return }
        startClient(target: .discovered(game), route: .game)
    }

    /// Gives up reconnecting to an interrupted game and forgets it.
    func cancelRejoin() {
        guard case .rejoining(let ref) = route, let session = remoteSession else { return }
        // The session forgets the game and its drafts after any draft write it still has queued.
        session.abandon()
        forget(gameID: ref.gameID)
        endSession()
    }

    /// Leaves the game for good (or closes one that already ended). As host this ends the game for everyone.
    func leaveGame() {
        guard let client else { return }
        client.leave()
        // `leave()` ends the game through the engine; shutting down directly also covers a rejected end.
        hostSession?.shutdown()
        if let remoteSession { finishLeaving(remoteSession) }
        endSession()
    }

    /// How long a leaving session gets to say goodbye before it's abandoned.
    static let leaveTimeout: Duration = .seconds(3)

    /// `leave()` waits for the host's ack and then says goodbye, so the session must stay alive until it
    /// reports `.ended`, or for `leaveTimeout` at most. Then it's torn down and, as a backstop, the game is
    /// forgotten so the next launch doesn't rejoin it.
    private func finishLeaving(_ session: any RemoteGameSession) {
        let gameID = session.state?.gameID
        departing.append(session)
        Task { [weak self] in
            for await isEnded in Observations({ session.hostStatus.isEnded }) where isEnded { break }
            self?.completeLeaving(session, gameID: gameID)
        }
        Task { [weak self, clock] in
            try? await clock.sleep(for: Self.leaveTimeout)
            self?.completeLeaving(session, gameID: gameID)
        }
    }

    private func completeLeaving(_ session: any RemoteGameSession, gameID: UUID?) {
        guard let index = departing.firstIndex(where: { $0 === session }) else { return }
        departing.remove(at: index)
        session.abandon()
        if let gameID { forget(gameID: gameID) }
    }

    /// Clears the active-game reference (if it still points at `gameID`) and that game's drafts.
    private func forget(gameID: UUID) {
        Task { [store] in
            if await store.loadActiveGame()?.gameID == gameID { await store.saveActiveGame(nil) }
            await store.clearDrafts(gameID: gameID)
        }
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            wasBackgrounded = true
            hostSession?.suspend()
            remoteSession?.suspend()
        case .active:
            // Going inactive and back (Control Center, a system alert) never suspended anything.
            guard wasBackgrounded else { return }
            wasBackgrounded = false
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

    /// While rejoining, moves to the game once state arrives. A session that ends returns to Home, except at
    /// game over, which stays on screen for the final standings.
    private func watch(_ session: any RemoteGameSession) {
        sessionWatch?.cancel()
        sessionWatch = Task { [weak self, weak session] in
            let changes = Observations { () -> (hasState: Bool, ended: EndReason?)? in
                guard let session else { return nil }
                if case .ended(let reason) = session.hostStatus { return (session.state != nil, reason) }
                return (session.state != nil, nil)
            }
            for await change in changes {
                guard let self, let change, self.remoteSession === session else { return }
                if let reason = change.ended {
                    // Task 17 explains versionMismatch / removed / gameClosed with an alert on Home.
                    let showsGameOver = reason == .gameOver && change.hasState && self.route == .game
                    if !showsGameOver {
                        session?.stop()
                        self.endSession()
                    }
                    return
                }
                if case .rejoining = self.route, change.hasState { self.route = .game }
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

extension HostStatus {
    var isEnded: Bool {
        if case .ended = self { true } else { false }
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
    /// `-openRoute hostSetup|join|practiceSetup`: open that screen instead of Home (screenshots, UI tests).
    var openRoute: AppModel.Route?

    init(arguments: [String]) {
        uiTesting = arguments.contains("-uiTesting")
        resetState = arguments.contains("-resetState")
        mockGame = arguments.contains("-mockGame")
        playerName = Self.value(after: "-playerName", in: arguments)
        openRoute = switch Self.value(after: "-openRoute", in: arguments) {
        case "hostSetup": .hostSetup
        case "join": .join
        case "practiceSetup": .practiceSetup
        default: nil
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// Whether the persisted store must be wiped before it's opened.
    var wipesStore: Bool { uiTesting || resetState }
}
