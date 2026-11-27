import Foundation
import Observation
import StopCore
import StopNetworking
import StopSession
import StopSimulation
import StopTestSupport
import Synchronization
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

    @Test func openRouteArgumentOpensScreen() async {
        let model = makeModel(arguments: ["-playerName", "Bia", "-openRoute", "join"])
        await model.bootstrap()
        #expect(model.route == .join)
        #expect(LaunchOptions(arguments: ["-openRoute", "game"]).openRoute == nil)
    }

    @Test func uiTestingDisablesSounds() async {
        _ = await saveProfile()
        let model = makeModel(arguments: ["-uiTesting"])
        await model.bootstrap()
        #expect(model.isUITesting)
        #expect(!model.soundsEnabled)
    }

    @Test func soundsToggleAppliesAtOnceAndIsPersisted() async throws {
        _ = await saveProfile()
        let model = makeModel()
        await model.bootstrap()
        #expect(model.soundsEnabled)
        model.setSoundsEnabled(false)
        #expect(!model.soundsEnabled)
        try await waitUntil { await store.loadProfile()?.soundsEnabled == false }
    }

    @Test func overlappingSavesKeepOnePlayerIDInOrder() async throws {
        let model = makeModel()
        await model.bootstrap()
        async let first: Void = model.saveName("Ana")
        async let second: Void = model.saveName("Ana")
        _ = await (first, second)
        model.setSoundsEnabled(false)
        await model.saveName("Bia")

        let saved = try #require(await store.loadProfile())
        #expect(saved == model.profile)
        #expect(saved.name == "Bia")
        #expect(!saved.soundsEnabled)
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

    @Test func cancelRejoinAbandonsSessionAndForgetsGame() async throws {
        _ = await saveProfile()
        let ref = ActiveGameRef(gameID: UUID(), role: .client, hostName: "Ana")
        await store.saveActiveGame(ref)
        await store.saveDraft(["Anta"], gameID: ref.gameID, round: 1)
        let model = makeModel()
        await model.bootstrap()
        let session = try #require(sessions.clients.first?.session)

        model.cancelRejoin()

        #expect(session.abandoned)
        #expect(model.route == .home)
        #expect(model.client == nil)
        try await waitUntil {
            let saved = await store.loadActiveGame()
            let draft = await store.loadDraft(gameID: ref.gameID, round: 1)
            return saved == nil && draft == nil
        }
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

    @Test func returningFromInactiveDoesNotResume() async throws {
        _ = await saveProfile()
        let model = makeModel()
        await model.bootstrap()
        model.join(try await discoverGame())
        let session = try #require(sessions.clients.first?.session)

        model.scenePhaseChanged(.inactive)
        model.scenePhaseChanged(.active)

        #expect(session.suspendCount == 0)
        #expect(session.resumeCount == 0)
    }

    @Test func leavingKeepsSessionAliveUntilItEnds() async throws {
        _ = await saveProfile()
        let model = makeModel()
        await model.bootstrap()
        model.join(try await discoverGame())
        let made = try #require(sessions.clients.first)
        let gameID = UUID()
        made.session.state = try GameEngine.newGame(
            gameID: gameID, hostID: UUID(), hostName: "Ana",
            settings: GameSettings(categories: ["Animal"], stopsRequired: 1, allowGiveUp: true), language: .en)
        await store.saveActiveGame(ActiveGameRef(gameID: gameID, role: .client, hostName: "Ana"))
        await store.saveDraft(["Anta"], gameID: gameID, round: 1)
        weak let weakSession = made.session
        sessions.forgetClients()

        model.leaveGame()

        #expect(model.route == .home)
        let session = try #require(weakSession)
        #expect(session.leftGame)
        #expect(!session.abandoned)

        session.hostStatus = .ended(.leftGame)  // the host acked; the session said goodbye

        try await waitUntil { session.abandoned }
        try await waitUntil {
            let ref = await store.loadActiveGame()
            let draft = await store.loadDraft(gameID: gameID, round: 1)
            return ref == nil && draft == nil
        }
    }

    @Test func leavingSessionThatNeverEndsIsAbandonedAfterTimeout() async throws {
        _ = await saveProfile()
        let clock = TestClock()
        let model = AppModel(store: store, factory: network, clock: clock, launchArguments: [],
                             sessions: sessions.factories)
        await model.bootstrap()
        model.join(try await discoverGame())
        let session = try #require(sessions.clients.first?.session)

        model.leaveGame()

        try await waitUntil { clock.sleeperCount == 1 }
        await clock.advance(by: AppModel.leaveTimeout - .milliseconds(1))
        #expect(!session.abandoned)
        await clock.advance(by: .milliseconds(1))
        try await waitUntil { session.abandoned }
    }

    @Test func sessionEndingMidGameRoutesHome() async throws {
        _ = await saveProfile()
        let model = makeModel()
        await model.bootstrap()
        model.join(try await discoverGame())
        let session = try #require(sessions.clients.first?.session)
        session.state = try GameEngine.newGame(
            gameID: UUID(), hostID: UUID(), hostName: "Ana",
            settings: GameSettings(categories: ["Animal"], stopsRequired: 1, allowGiveUp: true), language: .en)

        session.hostStatus = .ended(.removed)

        try await waitUntil { model.route == .home }
        #expect(model.client == nil)
        #expect(session.stopped)
    }

    @Test func gameOverStaysOnScreen() async throws {
        _ = await saveProfile()
        let model = makeModel()
        await model.bootstrap()
        model.join(try await discoverGame())
        let session = try #require(sessions.clients.first?.session)
        var state = try GameEngine.newGame(
            gameID: UUID(), hostID: UUID(), hostName: "Ana",
            settings: GameSettings(categories: ["Animal"], stopsRequired: 1, allowGiveUp: true), language: .en)
        state.phase = .gameOver
        session.state = state

        session.hostStatus = .ended(.gameOver)
        for _ in 0..<50 { await Task.yield() }  // give the watcher a chance to (wrongly) react

        #expect(model.route == .game)
        #expect(model.client === session)
    }

    @Test(arguments: [true, false])
    func unusableSavedHostGameIsDiscarded(gameOver: Bool) async throws {
        let profile = await saveProfile()
        var game = try GameEngine.newGame(
            gameID: UUID(), hostID: gameOver ? profile.playerID : UUID(), hostName: profile.name,
            settings: GameSettings(categories: ["Animal"], stopsRequired: 1, allowGiveUp: true), language: .en)
        if gameOver { game.phase = .gameOver }
        await store.saveHostGame(game)
        await store.saveActiveGame(ActiveGameRef(gameID: game.gameID, role: .host, hostName: profile.name))

        let model = makeModel()
        await model.bootstrap()

        #expect(model.route == .home)
        #expect(model.client == nil)
        #expect(await store.loadActiveGame() == nil)
        #expect(await store.loadHostGame() == nil)
    }

    @Test func wipingTheStoreDeletesOnlyItsFolder() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "Stop", directoryHint: .isDirectory)
        let sibling = root.appending(path: "Other.txt")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: sibling)
        try Data("old".utf8).write(to: folder.appending(path: "profile.json"))

        _ = StoreLocation.makeStore(wipe: true, directory: folder)

        #expect(FileManager.default.fileExists(atPath: sibling.path))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "profile.json").path))
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
        try await waitUntil { client.state?.players.map(\.name).sorted() == ["Ana", "Bia", "Caio", "Gui"] }
        model.leaveGame()
    }

    // MARK: Practice

    func startPractice(_ model: AppModel, bots: Int = 3, speed: BotSpeed = .fast) {
        model.startPractice(settings: GameSettings(categories: ["Animal", "Fruit"], stopsRequired: 1,
                                                   allowGiveUp: true),
                            botNames: Array(PracticeSetupModel.botNames(for: .en).prefix(bots)), speed: speed)
    }

    @Test func practiceStartsInTheLobbyWithBotsJoined() async throws {
        _ = await saveProfile()
        let model = makeModel()
        await model.bootstrap()

        startPractice(model, bots: 2, speed: .relaxed)

        #expect(model.route == .game)
        #expect(model.isPractice)
        let launch = try #require(sessions.practiceLaunches.first)
        #expect(launch.botNames == ["Robo Ana", "Robo Ben"])
        #expect(launch.speed == .relaxed)
        let client = try #require(model.client)
        #expect(client.isHost)
        try await waitUntil {
            client.state?.players.map(\.name).sorted() == ["Gui", "Robo Ana", "Robo Ben"]
                && client.state?.players.allSatisfy { $0.presence == .present } == true
        }
        #expect(client.state?.phase == .lobby)
        model.leaveGame()
        #expect(model.route == .home)
        #expect(!model.isPractice)
    }

    @Test func practiceNotRestoredAfterKill() async throws {
        _ = await saveProfile()
        let model = makeModel()
        await model.bootstrap()
        startPractice(model)
        let client = try #require(model.client)
        try await waitUntil { client.state?.players.count == 4 }
        client.send(.startGame)
        try await waitUntil { client.state?.phase != .lobby }
        // A hosted game would be saved by now (see `hostGameStartsHostSessionAndPersistsIt`); practice never is.
        #expect(await store.loadActiveGame() == nil)
        #expect(await store.loadHostGame() == nil)

        // The app is killed mid-round: a fresh launch on the same store goes Home.
        let relaunched = makeModel()
        await relaunched.bootstrap()
        #expect(relaunched.route == .home)
        #expect(relaunched.client == nil)
        #expect(!relaunched.isPractice)
        model.leaveGame()
    }

    @Test func practiceGameNeverUsesRealNetwork() async throws {
        _ = await saveProfile()
        let realNetwork = FactorySpy()
        let model = AppModel(store: store, factory: realNetwork, launchArguments: [], sessions: sessions.factories)
        await model.bootstrap()

        startPractice(model, bots: 5)

        let client = try #require(model.client)
        try await waitUntil { client.state?.players.count == 6 }
        client.send(.startGame)
        try await waitUntil { client.state?.phase != .lobby }
        model.leaveGame()
        #expect(realNetwork.uses == 0)
    }

    @Test func endingPracticeStopsTheBots() async throws {
        _ = await saveProfile()
        let model = makeModel()
        await model.bootstrap()
        startPractice(model, bots: 1)
        let client = try #require(model.client)
        try await waitUntil { client.state?.players.count == 2 }
        let bot = try #require(sessions.practiceLaunches.first?.game?.retained.compactMap { $0 as? BotPlayer }.first)

        model.leaveGame()

        try await waitUntil { bot.client.hostStatus.isEnded }
    }

    @Test func practiceIsIgnoredWhileInAGame() async throws {
        _ = await saveProfile()
        let model = makeModel()
        await model.bootstrap()
        model.hostGame(settings: GameSettings(categories: ["Animal"], stopsRequired: 1, allowGiveUp: true))
        startPractice(model)
        #expect(sessions.practiceLaunches.isEmpty)
        #expect(!model.isPractice)
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

    // MARK: Live session wiring

    @Test func gameLanguageFollowsLocale() {
        #expect(AppModel.language(for: Locale(identifier: "pt_BR")) == .ptBR)
        #expect(AppModel.language(for: Locale(identifier: "pt_PT")) == .ptBR)
        #expect(AppModel.language(for: Locale(identifier: "en_US")) == .en)
        #expect(AppModel.language(for: Locale(identifier: "fr_FR")) == .en)
    }

    @Test func clientTargetMapsToSessionTarget() async throws {
        let id = UUID()
        guard case .rejoin(let gameID) = ClientTarget.rejoin(gameID: id).sessionTarget else {
            Issue.record("expected .rejoin")
            return
        }
        #expect(gameID == id)
        let game = try await discoverGame()
        guard case .discovered(let mapped) = ClientTarget.discovered(game).sessionTarget else {
            Issue.record("expected .discovered")
            return
        }
        #expect(mapped == game)
    }

    @Test func liveFactoryMakesClientSession() {
        let profile = Profile(playerID: UUID(), name: "Gui", soundsEnabled: true)
        let session = SessionFactories.live.makeClient(profile, .rejoin(gameID: UUID()), network, store,
                                                       ContinuousClock())
        #expect(session is ClientSession)
        #expect(session.localPlayerID == profile.playerID)
    }

    @Test func joiningRealHostThenLeaving() async throws {
        _ = await saveProfile("Bia")
        let hostID = UUID()
        let state = try GameEngine.newGame(
            gameID: UUID(), hostID: hostID, hostName: "Ana",
            settings: GameSettings(categories: ["Animal"], stopsRequired: 1, allowGiveUp: false), language: .en)
        let host = HostSession(state: state, factory: network, store: InMemoryGameStore(), clock: ContinuousClock())
        host.start()
        defer { host.shutdown() }
        let model = AppModel(store: store, factory: network, launchArguments: [], sessions: .live)
        await model.bootstrap()

        model.join(try await discoverGame(hostName: "Ana"))

        try await waitUntil { model.client?.state?.players.map(\.name) == ["Ana", "Bia"] }
        let playerID = try #require(model.profile?.playerID)

        model.leaveGame()

        #expect(model.route == .home)
        try await waitUntil { host.localClient.state?.player(playerID)?.presence == .left }
    }

    // MARK: Helpers

    /// A real advertised game on the in-memory network, found by browsing (failing after 3 s). With a
    /// `hostName`, finds that host's game (already advertised) instead of advertising a new one.
    private func discoverGame(hostName: String? = nil) async throws -> DiscoveredGame {
        if hostName == nil {
            let listener = network.makeListener()
            let ad = Advertisement(gameID: UUID(), hostName: "Ana", playerCount: 1, protocolVersion: 1, joinable: true)
            _ = listener.start(advertising: ad)
        }
        let browser = network.makeBrowser()
        defer { browser.stop() }
        let events = browser.start()
        let deadline = Task {
            try? await Task.sleep(for: .seconds(3))
            browser.stop()
        }
        defer { deadline.cancel() }
        for await event in events {
            if case .results(let games) = event,
               let game = games.first(where: { hostName == nil || $0.advertisement.hostName == hostName }) {
                return game
            }
        }
        Issue.record("no game discovered within 3 s")
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
    private(set) var abandoned = false
    /// `leave()` was called. Like `ClientSession`, the fake doesn't end at once; tests set `hostStatus`.
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
    func abandon() {
        abandoned = true
        stopped = true
        if case .ended = hostStatus { return }
        hostStatus = .ended(.leftGame)
    }
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

    /// Drops the spy's references, so a test can check who else keeps a session alive.
    func forgetClients() { clients = [] }
    private(set) var mockLaunches: [MockLaunch] = []

    struct PracticeLaunch {
        let botNames: [String]
        let speed: BotSpeed
        let game: MockGame?
    }

    private(set) var practiceLaunches: [PracticeLaunch] = []

    var factories: SessionFactories {
        SessionFactories(
            makeClient: { [unowned self] profile, target, _, _, _ in
                let session = FakeRemoteSession(playerID: profile.playerID)
                clients.append(MadeClient(profile: profile, target: target, session: session))
                return session
            },
            launchMockGame: { [unowned self] profile, botNames, settings, language, clock in
                mockLaunches.append(MockLaunch(hostProfile: profile, botNames: botNames))
                return SessionFactories.idleBotsMockGame(
                    hostProfile: profile, botNames: botNames, settings: settings, language: language, clock: clock)
            },
            launchPractice: { [unowned self] profile, botNames, settings, language, speed, store, clock in
                // The real launcher: practice games must really run on their own in-memory network.
                let game = SessionFactories.live.launchPractice(profile, botNames, settings, language, speed, store,
                                                                clock)
                practiceLaunches.append(PracticeLaunch(botNames: botNames, speed: speed, game: game))
                return game
            })
    }
}

/// A transport factory that counts every use (practice must never touch the app's real network).
final class FactorySpy: TransportFactory {
    private let network = InMemoryNetwork()
    private let count = Mutex(0)

    var uses: Int { count.withLock { $0 } }

    func makeListener() -> any Listener {
        count.withLock { $0 += 1 }
        return network.makeListener()
    }

    func makeBrowser() -> any Browser {
        count.withLock { $0 += 1 }
        return network.makeBrowser()
    }

    func connect(to endpoint: EndpointRef) -> any Connection {
        count.withLock { $0 += 1 }
        return network.connect(to: endpoint)
    }
}
