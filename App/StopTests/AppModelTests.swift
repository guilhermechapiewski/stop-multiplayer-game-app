import Foundation
import Observation
import StopCore
import StopNetworking
import StopSession
import Testing
@testable import Stop

@MainActor
struct AppModelTests {
    let store = InMemoryGameStore()
    let network = InMemoryNetwork()
    let sessions = SessionSpy()

    func makeModel(arguments: [String] = []) -> AppModel {
        AppModel(store: store, factory: network, launchArguments: arguments, sessions: sessions.factories)
    }

    func saveProfile(_ name: String = "Gui") async -> Profile {
        let profile = Profile(playerID: UUID(), name: name, soundsEnabled: true)
        await store.saveProfile(profile)
        return profile
    }

    // MARK: Version and About

    @Test func appVersionDisplayFormat() {
        #expect(AppVersion.display(short: "1.0", build: "1") == "1.0 (1)")
    }

    @Test func aboutLinksPointAtProjectSite() {
        let site = "https://guilhermechapiewski.github.io/stop-multiplayer-game-app"
        #expect(AboutLinks.privacyPolicy(languageCode: "en").absoluteString == site + "/privacy/")
        #expect(AboutLinks.privacyPolicy(languageCode: "pt-BR").absoluteString == site + "/pt/privacidade/")
        #expect(AboutLinks.privacyPolicy(languageCode: "pt").absoluteString == site + "/pt/privacidade/")
        #expect(AboutLinks.sourceCode.absoluteString == "https://github.com/guilhermechapiewski/stop-multiplayer-game-app")
        #expect(AboutLinks.reportProblem.absoluteString.hasPrefix(
            "https://github.com/guilhermechapiewski/stop-multiplayer-game-app/issues"))
    }

    // MARK: Launch routing

    @Test func firstLaunchRoutesToOnboarding() async {
        let model = makeModel()
        #expect(model.route == .loading)
        await model.bootstrap()
        #expect(model.route == .onboarding)
        #expect(model.profile == nil)
    }

    @Test func savingNameCreatesProfileAndRoutesHome() async {
        let model = makeModel()
        await model.bootstrap()
        await model.saveName("  Gui  ")
        #expect(model.route == .home)
        #expect(model.profile?.name == "Gui")
        #expect(await store.loadProfile() == model.profile)
    }

    @Test func blankNameIsIgnored() async {
        let model = makeModel()
        await model.bootstrap()
        await model.saveName("   ")
        #expect(model.route == .onboarding)
        #expect(await store.loadProfile() == nil)
    }

    @Test func renameKeepsPlayerID() async {
        let saved = await saveProfile()
        let model = makeModel()
        await model.bootstrap()
        await model.saveName("Ana")
        #expect(model.profile?.playerID == saved.playerID)
        #expect(model.profile?.name == "Ana")
        #expect(model.route == .home)
    }

    @Test func savedProfileRoutesHome() async {
        let saved = await saveProfile()
        let model = makeModel()
        await model.bootstrap()
        #expect(model.route == .home)
        #expect(model.profile == saved)
    }

    @Test func playerNameArgumentSkipsOnboarding() async {
        let model = makeModel(arguments: ["-playerName", "Bia"])
        await model.bootstrap()
        #expect(model.route == .home)
        #expect(model.profile?.name == "Bia")
    }

    @Test func uiTestingDisablesSounds() async {
        _ = await saveProfile()
        let model = makeModel(arguments: ["-uiTesting"])
        await model.bootstrap()
        #expect(model.isUITesting)
        #expect(!model.soundsEnabled)
    }

    @Test func soundsToggleIsPersisted() async {
        _ = await saveProfile()
        let model = makeModel()
        await model.bootstrap()
        #expect(model.soundsEnabled)
        await model.setSoundsEnabled(false)
        #expect(!model.soundsEnabled)
        #expect(await store.loadProfile()?.soundsEnabled == false)
    }

    // MARK: Restoring games

    @Test func activeHostGameRestoresOnLaunch() async throws {
        let profile = await saveProfile()
        let game = try GameEngine.newGame(
            gameID: UUID(), hostID: profile.playerID, hostName: profile.name,
            settings: GameSettings(categories: ["Animal"], stopsRequired: 1, allowGiveUp: true), language: .en)
        await store.saveHostGame(game)
        await store.saveActiveGame(ActiveGameRef(gameID: game.gameID, role: .host, hostName: profile.name))

        let model = makeModel()
        await model.bootstrap()

        #expect(model.route == .game)
        let client = try #require(model.client)
        #expect(client.isHost)
        #expect(client.state?.gameID == game.gameID)
        model.leaveGame()
    }

    @Test func activeHostRefWithoutSavedGameRoutesHomeAndClearsRef() async {
        let profile = await saveProfile()
        await store.saveActiveGame(ActiveGameRef(gameID: UUID(), role: .host, hostName: profile.name))
        let model = makeModel()
        await model.bootstrap()
        #expect(model.route == .home)
        #expect(model.client == nil)
        #expect(await store.loadActiveGame() == nil)
    }

    @Test func activeClientGameRoutesToRejoining() async throws {
        let profile = await saveProfile()
        let ref = ActiveGameRef(gameID: UUID(), role: .client, hostName: "Ana")
        await store.saveActiveGame(ref)

        let model = makeModel()
        await model.bootstrap()

        #expect(model.route == .rejoining(ref))
        let made = try #require(sessions.clients.first)
        #expect(made.target == .rejoin(gameID: ref.gameID))
        #expect(made.profile == profile)
        #expect(made.session.started)
        #expect(model.client === made.session)
    }

    @Test func rejoinCompletesWhenStateArrives() async throws {
        _ = await saveProfile()
        let ref = ActiveGameRef(gameID: UUID(), role: .client, hostName: "Ana")
        await store.saveActiveGame(ref)
        let model = makeModel()
        await model.bootstrap()
        let session = try #require(sessions.clients.first?.session)

        session.state = try GameEngine.newGame(
            gameID: ref.gameID, hostID: UUID(), hostName: "Ana",
            settings: GameSettings(categories: ["Animal"], stopsRequired: 1, allowGiveUp: true), language: .en)

        try await waitUntil { model.route == .game }
    }

    @Test func rejoinEndingRoutesHome() async throws {
        _ = await saveProfile()
        let ref = ActiveGameRef(gameID: UUID(), role: .client, hostName: "Ana")
        await store.saveActiveGame(ref)
        let model = makeModel()
        await model.bootstrap()
        let session = try #require(sessions.clients.first?.session)

        session.hostStatus = .ended(.gameClosed)

        try await waitUntil { model.route == .home }
        #expect(model.client == nil)
    }

    @Test func cancelRejoinStopsSessionAndForgetsGame() async throws {
        _ = await saveProfile()
        let ref = ActiveGameRef(gameID: UUID(), role: .client, hostName: "Ana")
        await store.saveActiveGame(ref)
        let model = makeModel()
        await model.bootstrap()
        let session = try #require(sessions.clients.first?.session)

        model.cancelRejoin()

        #expect(session.stopped)
        #expect(model.route == .home)
        #expect(model.client == nil)
        try await waitUntil { await store.loadActiveGame() == nil }
    }

    // MARK: Playing

    @Test func hostGameStartsHostSessionAndPersistsIt() async throws {
        _ = await saveProfile()
        let model = makeModel()
        await model.bootstrap()

        model.hostGame(settings: GameSettings(categories: ["Animal", "Fruit"], stopsRequired: 1, allowGiveUp: true))

        #expect(model.route == .game)
        let client = try #require(model.client)
        #expect(client.isHost)
        #expect(client.state?.settings.categories == ["Animal", "Fruit"])
        try await waitUntil { await store.loadActiveGame()?.role == .host }
        model.leaveGame()
    }

    @Test func joinStartsClientSessionForDiscoveredGame() async throws {
        let profile = await saveProfile()
        let model = makeModel()
        await model.bootstrap()
        let game = try await discoverGame()

        model.join(game)

        #expect(model.route == .game)
        let made = try #require(sessions.clients.first)
        #expect(made.target == .discovered(game))
        #expect(made.profile == profile)
        #expect(made.session.started)
    }

    @Test func leaveGameClearsActiveGameAndRoutesHome() async throws {
        _ = await saveProfile()
        let model = makeModel()
        await model.bootstrap()
        model.hostGame(settings: GameSettings(categories: ["Animal"], stopsRequired: 1, allowGiveUp: true))
        try await waitUntil { await store.loadActiveGame() != nil }

        model.leaveGame()

        #expect(model.route == .home)
        #expect(model.client == nil)
        try await waitUntil {
            let ref = await store.loadActiveGame()
            let game = await store.loadHostGame()
            return ref == nil && game == nil
        }
    }

    @Test func leavingAsClientCallsLeave() async throws {
        _ = await saveProfile()
        let model = makeModel()
        await model.bootstrap()
        model.join(try await discoverGame())
        let session = try #require(sessions.clients.first?.session)

        model.leaveGame()

        #expect(session.leftGame)
        #expect(model.route == .home)
        #expect(model.client == nil)
    }

    @Test func scenePhaseSuspendsAndResumesClientSession() async throws {
        _ = await saveProfile()
        let model = makeModel()
        await model.bootstrap()
        model.join(try await discoverGame())
        let session = try #require(sessions.clients.first?.session)

        model.scenePhaseChanged(.background)
        #expect(session.suspendCount == 1)
        model.scenePhaseChanged(.inactive)
        #expect(session.suspendCount == 1)
        model.scenePhaseChanged(.active)
        #expect(session.resumeCount == 1)
    }

    @Test func mockGameArgumentStartsHostWithThreeBots() async throws {
        let model = makeModel(arguments: ["-mockGame", "-playerName", "Gui"])
        await model.bootstrap()

        #expect(model.route == .game)
        let launch = try #require(sessions.mockLaunches.first)
        #expect(launch.botNames == ["Ana", "Bia", "Caio"])
        #expect(launch.hostProfile.name == "Gui")
        let client = try #require(model.client)
        #expect(client.isHost)
        #expect(client.state?.players.first?.name == "Gui")
        model.leaveGame()
    }

    @Test func navigationBetweenMenuRoutes() async {
        _ = await saveProfile()
        let model = makeModel()
        await model.bootstrap()
        for route in [AppModel.Route.hostSetup, .join, .practiceSetup] {
            model.navigate(to: route)
            #expect(model.route == route)
            model.navigate(to: .home)
            #expect(model.route == .home)
        }
        model.navigate(to: .game)  // only menu routes are reachable this way
        #expect(model.route == .home)
    }

    // MARK: Helpers

    /// A real advertised game on the in-memory network, found by browsing.
    private func discoverGame() async throws -> DiscoveredGame {
        let listener = network.makeListener()
        let ad = Advertisement(gameID: UUID(), hostName: "Ana", playerCount: 1, protocolVersion: 1, joinable: true)
        _ = listener.start(advertising: ad)
        let browser = network.makeBrowser()
        defer { browser.stop() }
        for await event in browser.start() {
            if case .results(let games) = event, let game = games.first { return game }
        }
        throw CancellationError()
    }
}

/// Polls `condition` on the main actor until it holds, failing after `timeout`.
@MainActor
func waitUntil(timeout: Duration = .seconds(3), _ condition: @MainActor () async -> Bool,
               sourceLocation: SourceLocation = #_sourceLocation) async throws {
    let deadline = ContinuousClock.now + timeout
    while await !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("condition not met within \(timeout)", sourceLocation: sourceLocation)
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

// MARK: Session doubles

@MainActor @Observable
final class FakeRemoteSession: RemoteGameSession {
    let localPlayerID: PlayerID
    var isHost: Bool { false }
    var state: GameState?
    var hostStatus: HostStatus = .connecting
    let presenceChanges = AsyncStream<PresenceChange> { _ in }
    var lastError: GameError?
    var frozenAnswers: [String]?

    private(set) var started = false
    private(set) var stopped = false
    private(set) var leftGame = false
    private(set) var suspendCount = 0
    private(set) var resumeCount = 0

    init(playerID: PlayerID) { localPlayerID = playerID }

    func send(_ intent: Intent) {}
    func saveDraft(_ answers: [String]) {}
    func draft() async -> [String]? { nil }
    func leave() { leftGame = true }
    func start() { started = true }
    func suspend() { suspendCount += 1 }
    func resume() { resumeCount += 1 }
    func stop() { stopped = true }
}

@MainActor
final class SessionSpy {
    struct MadeClient {
        let profile: Profile
        let target: ClientTarget
        let session: FakeRemoteSession
    }

    struct MockLaunch {
        let hostProfile: Profile
        let botNames: [String]
    }

    private(set) var clients: [MadeClient] = []
    private(set) var mockLaunches: [MockLaunch] = []

    var factories: SessionFactories {
        SessionFactories(
            makeClient: { [unowned self] profile, target, _, _, _ in
                let session = FakeRemoteSession(playerID: profile.playerID)
                clients.append(MadeClient(profile: profile, target: target, session: session))
                return session
            },
            launchMockGame: { [unowned self] profile, botNames, settings, language, clock in
                mockLaunches.append(MockLaunch(hostProfile: profile, botNames: botNames))
                return SessionFactories.hostOnlyMockGame(
                    hostProfile: profile, botNames: botNames, settings: settings, language: language, clock: clock)
            })
    }
}
