import Foundation
import StopCore
import StopNetworking
import StopSession
import StopTestSupport
import Testing
@testable import Stop

/// Backgrounding, relaunching, ended sessions, the idle timer and presence banners.
@MainActor
struct AppModelInterruptionTests {
    let store = InMemoryGameStore()
    let network = InMemoryNetwork()
    let sessions = SessionSpy()
    let clock = TestClock()
    let backgroundTasks = BackgroundTaskSpy()

    func makeModel() -> AppModel {
        AppModel(store: store, factory: network, clock: clock, launchArguments: [], sessions: sessions.factories,
                 backgroundTasks: backgroundTasks.tasks)
    }

    func profile() async -> Profile {
        let profile = Profile(playerID: UUID(), name: "Gui", soundsEnabled: true)
        await store.saveProfile(profile)
        return profile
    }

    /// A model rejoining a game Ana hosts, with the session it made.
    func rejoining() async throws -> (AppModel, FakeRemoteSession, ActiveGameRef) {
        _ = await profile()
        let ref = ActiveGameRef(gameID: UUID(), role: .client, hostName: "Ana")
        await store.saveActiveGame(ref)
        let model = makeModel()
        await model.bootstrap()
        let session = try #require(sessions.clients.first?.session)
        return (model, session, ref)
    }

    func state(gameID: UUID, me: PlayerID, phase: Phase = .lobby) throws -> GameState {
        var state = try GameEngine.newGame(
            gameID: gameID, hostID: UUID(), hostName: "Ana",
            settings: GameSettings(categories: ["Animal"], stopsRequired: 1, allowGiveUp: false), language: .en)
        state.players.append(Player(id: me, name: "Gui", presence: .present))
        state.players.append(Player(id: UUID(), name: "Bia", presence: .present))
        state.phase = phase
        return state
    }

    // MARK: Scene phase

    @Test func backgroundSuspendsActiveSession() async throws {
        let (model, session, ref) = try await rejoining()
        session.state = try state(gameID: ref.gameID, me: session.localPlayerID)
        try await waitUntil { model.route == .game }

        model.scenePhaseChanged(.background)

        #expect(session.suspendCount == 1)
        // The suspension runs in background time, which ends after the grace period.
        #expect(backgroundTasks.begun == 1)
        #expect(backgroundTasks.ended == 0)
        try await waitUntil { clock.sleeperCount > 0 }
        await clock.advance(by: AppModel.suspendGrace)
        try await waitUntil { backgroundTasks.ended == 1 }
    }

    @Test func backgroundWithoutAGameAsksForNoBackgroundTime() async {
        _ = await profile()
        let model = makeModel()
        await model.bootstrap()
        model.scenePhaseChanged(.background)
        #expect(backgroundTasks.begun == 0)
    }

    @Test func activeResumesSession() async throws {
        let (model, session, _) = try await rejoining()
        model.scenePhaseChanged(.background)
        model.scenePhaseChanged(.inactive)
        model.scenePhaseChanged(.active)
        #expect(session.resumeCount == 1)
        // A second activation without a background in between doesn't resume again.
        model.scenePhaseChanged(.active)
        #expect(session.resumeCount == 1)
    }

    // MARK: Relaunch

    @Test func relaunchWithClientRefShowsRejoiningThenGame() async throws {
        let (model, session, ref) = try await rejoining()
        #expect(model.route == .rejoining(ref))
        #expect(sessions.clients.first?.target == .rejoin(gameID: ref.gameID))
        #expect(session.started)

        session.hostStatus = .connected
        session.state = try state(gameID: ref.gameID, me: session.localPlayerID, phase: .writing)
        try await waitUntil { model.route == .game }
    }

    @Test func cancelRejoinClearsRef() async throws {
        let (model, session, _) = try await rejoining()
        model.cancelRejoin()
        #expect(session.abandoned)
        #expect(model.route == .home)
        try await waitUntil { await store.loadActiveGame() == nil }
    }

    @Test func rejoiningExposesLocalNetworkDenial() async throws {
        let (model, session, _) = try await rejoining()
        #expect(!model.isLocalNetworkDenied)
        session.isLocalNetworkDenied = true
        #expect(model.isLocalNetworkDenied)
    }

    // MARK: Ended sessions

    @Test(arguments: [EndReason.removed, .versionMismatch, .gameClosed])
    func endingWithAnExplanationRoutesHomeWithNotice(reason: EndReason) async throws {
        let (model, session, ref) = try await rejoining()
        session.state = try state(gameID: ref.gameID, me: session.localPlayerID)
        try await waitUntil { model.route == .game }

        session.hostStatus = .ended(reason)

        try await waitUntil { model.route == .home }
        #expect(model.endNotice == reason)
        model.dismissEndNotice()
        #expect(model.endNotice == nil)
    }

    @Test func endingWhileRejoiningExplainsToo() async throws {
        let (model, session, _) = try await rejoining()
        session.hostStatus = .ended(.gameClosed)
        try await waitUntil { model.route == .home }
        #expect(model.endNotice == .gameClosed)
    }

    @Test func leavingShowsNoNotice() async throws {
        let (model, session, ref) = try await rejoining()
        session.state = try state(gameID: ref.gameID, me: session.localPlayerID)
        try await waitUntil { model.route == .game }
        model.leaveGame()
        session.hostStatus = .ended(.leftGame)
        #expect(model.route == .home)
        #expect(model.endNotice == nil)
    }

    // MARK: Idle timer

    @Test func screenStaysAwakeDuringAGameUntilGameOver() async throws {
        let (model, session, ref) = try await rejoining()
        #expect(!model.keepsScreenAwake)
        session.state = try state(gameID: ref.gameID, me: session.localPlayerID, phase: .writing)
        try await waitUntil { model.route == .game }
        #expect(model.keepsScreenAwake)

        session.state?.phase = .gameOver
        #expect(!model.keepsScreenAwake)
    }

    // MARK: Banners

    @Test func presenceChangesBecomeBanners() async throws {
        let (model, session, ref) = try await rejoining()
        let state = try state(gameID: ref.gameID, me: session.localPlayerID)
        session.state = state
        let bia = try #require(state.players.first { $0.name == "Bia" })

        session.presenceEvents.yield(PresenceChange(playerID: bia.id, kind: .wentAway))

        try await waitUntil { model.banners?.current?.text == "Bia left the app" }
    }
}

/// Records background time asked for and given back.
@MainActor
final class BackgroundTaskSpy {
    private(set) var begun = 0
    private(set) var ended = 0

    var tasks: BackgroundTasks {
        BackgroundTasks { [unowned self] _ in
            begun += 1
            return { [unowned self] in ended += 1 }
        }
    }
}
