import Foundation
import StopCore
import StopNetworking
import StopTestSupport
import Testing
@testable import StopSession

private let categories = ["Name", "Animal"]

/// Polls `condition` (yielding a millisecond between checks) and records an issue if it never holds.
@MainActor
private func waitUntil(_ what: String, _ condition: () async -> Bool) async {
    for _ in 0..<3000 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("timed out waiting for \(what)")
}

/// A test peer that speaks raw `WireMessage`s over an in-memory connection.
@MainActor
private final class RawClient {
    let playerID: PlayerID
    let connection: any Connection
    private var events: AsyncStream<ConnectionEvent>.Iterator
    private(set) var isClosed = false

    init(_ connection: any Connection, playerID: PlayerID) {
        self.connection = connection
        self.playerID = playerID
        events = connection.events.makeAsyncIterator()
        connection.start()
    }

    func send(_ body: WireMessage.Body, protocolVersion: Int = currentProtocolVersion) {
        connection.send((try? WireMessage(protocolVersion: protocolVersion, body: body).encoded()) ?? Data())
    }

    @discardableResult
    func send(_ intent: Intent, id: UUID = UUID()) -> UUID {
        send(.intent(id: id, intent))
        return id
    }

    /// The next message other than a heartbeat; nil once the connection closed.
    func next() async -> WireMessage.Body? {
        while true {
            var iterator = events
            let next = await iterator.next(isolation: #isolation)
            events = iterator
            guard let event = next else { break }
            switch event {
            case .ready: continue
            case .closed: isClosed = true; return nil
            case .message(let data):
                guard let message = try? WireMessage.decode(data), message.body != .heartbeat else { continue }
                return message.body
            }
        }
        isClosed = true
        return nil
    }

    func nextSnapshot(where predicate: (GameState) -> Bool = { _ in true }) async -> GameState? {
        while let body = await next() {
            if case .snapshot(let state) = body, predicate(state) { return state }
        }
        return nil
    }

    func nextAck() async -> WireMessage.Body? {
        while let body = await next() {
            if case .ack = body { return body }
        }
        return nil
    }

    func untilClosed() async -> Bool {
        while await next() != nil {}
        return isClosed
    }
}

@MainActor
private final class Harness {
    let net = InMemoryNetwork()
    let clock = TestClock()
    let store = InMemoryGameStore()
    let host: HostSession
    var hostID: PlayerID { host.state.hostID }

    init(state: GameState? = nil, stopsRequired: Int = 1, awayAfter: Duration = .seconds(3600)) throws {
        let initial: GameState
        if let state {
            initial = state
        } else {
            initial = try Harness.newGame(stopsRequired: stopsRequired)
        }
        var timing = SessionTiming()
        timing.awayAfter = awayAfter
        host = HostSession(state: initial, factory: net, store: store, clock: clock, timing: timing)
        host.start()
    }

    static func newGame(stopsRequired: Int = 1) throws -> GameState {
        try GameEngine.newGame(
            gameID: UUID(), hostID: UUID(), hostName: "Gui",
            settings: GameSettings(categories: categories, stopsRequired: stopsRequired, allowGiveUp: true),
            language: .en)
    }

    func browse(until predicate: (Advertisement) -> Bool = { _ in true }) async -> DiscoveredGame? {
        let browser = net.makeBrowser()
        defer { browser.stop() }
        for await event in browser.start() {
            if case .results(let games) = event, let game = games.first, predicate(game.advertisement) { return game }
        }
        return nil
    }

    /// Connects and sends `.hello`; doesn't wait for the reply.
    func connect(_ id: PlayerID = UUID(), name: String = "Ana", gameID: UUID? = nil,
                 protocolVersion: Int = currentProtocolVersion) async throws -> RawClient {
        let game = try #require(await browse())
        let client = RawClient(net.connect(to: game.endpoint), playerID: id)
        client.send(.hello(playerID: id, name: name, gameID: gameID, lastVersion: nil),
                    protocolVersion: protocolVersion)
        return client
    }

    /// Connects, expects `.welcome` and waits until the host sees the player present.
    func join(_ name: String = "Ana", id: PlayerID = UUID()) async throws -> RawClient {
        let client = try await connect(id, name: name)
        guard case .welcome(let state) = await client.next() else {
            Issue.record("expected welcome")
            throw CancellationError()
        }
        #expect(state.player(id)?.presence == .present)
        await waitUntil("\(name) present") { host.state.player(id)?.presence == .present }
        return client
    }

    /// Advances the clock one second at a time, letting the host's loops (`sleepers` of them) re-arm each step.
    func advance(seconds: Int, sleepers: Int = 2) async {
        for _ in 0..<seconds {
            await waitUntil("\(sleepers) sleepers") { clock.sleeperCount >= sleepers }
            await clock.advance(by: .seconds(1))
        }
        await waitUntil("\(sleepers) sleepers") { clock.sleeperCount >= sleepers }
    }

    /// Starts the game and ticks through the reveal and countdown.
    func toWriting() async {
        host.localClient.send(.startGame)
        await advance(seconds: 5)
        #expect(host.state.phase == .writing)
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct HostSessionTests {
    @Test func helloJoinsAndReceivesWelcome() async throws {
        let h = try Harness()
        let ana = try await h.connect(name: "Ana")
        guard case .welcome(let state) = await ana.next() else { Issue.record("expected welcome"); return }
        #expect(state.gameID == h.host.state.gameID)
        #expect(state.players.map(\.name) == ["Gui", "Ana"])
        #expect(h.host.state.player(ana.playerID)?.presence == .present)
    }

    @Test func versionMismatchRejected() async throws {
        let h = try Harness()
        let old = try await h.connect(protocolVersion: currentProtocolVersion + 1)
        #expect(await old.next() == .rejected(.versionMismatch))
        #expect(await old.untilClosed())
        #expect(h.host.state.players.count == 1)
    }

    @Test func wrongGameRejected() async throws {
        let h = try Harness()
        let stray = try await h.connect(gameID: UUID())
        #expect(await stray.next() == .rejected(.wrongGame))
        #expect(await stray.untilClosed())
    }

    @Test func newPlayerRejectedAfterStart() async throws {
        let h = try Harness()
        _ = try await h.join("Ana")
        h.host.localClient.send(.startGame)
        let late = try await h.connect(name: "Bea")
        #expect(await late.next() == .rejected(.gameClosed))
        #expect(await late.untilClosed())
        #expect(h.host.state.player(late.playerID) == nil)
    }

    @Test func knownPlayerReconnectsAfterStart() async throws {
        let h = try Harness()
        let ana = try await h.join("Ana")
        h.host.localClient.send(.startGame)
        h.net.severClient(ana.connection.id)
        await waitUntil("Ana away") { h.host.state.player(ana.playerID)?.presence == .away }
        let again = try await h.connect(ana.playerID, name: "Ana")
        guard case .welcome(let state) = await again.next() else { Issue.record("expected welcome"); return }
        #expect(state.player(ana.playerID)?.presence == .present)
        #expect(state.currentRound?.participants.contains(ana.playerID) == true)
    }

    @Test func intentsAckedAndDeduplicated() async throws {
        let h = try Harness(stopsRequired: 2)
        let ana = try await h.join("Ana")
        _ = try await h.join("Bea")
        await h.toWriting()
        let before = h.host.state.version
        let id = UUID()
        ana.send(.stop(answers: ["Ana", "Anta"]), id: id)
        ana.send(.stop(answers: ["Ana", "Anta"]), id: id)
        #expect(await ana.nextAck() == .ack(id: id, error: nil))
        #expect(await ana.nextAck() == .ack(id: id, error: nil))
        #expect(h.host.state.version == before + 1)
        #expect(h.host.state.currentRound?.stops.count == 1)
    }

    @Test func rejectedIntentAckedWithError() async throws {
        let h = try Harness()
        let ana = try await h.join("Ana")
        await h.toWriting()
        h.host.localClient.send(.stop(answers: ["Gui", "Gato"]))
        #expect(h.host.state.phase == .collecting)
        #expect(h.host.localClient.frozenAnswers == ["Gui", "Gato"])
        let id = ana.send(.stop(answers: ["Ana", "Anta"]))
        #expect(await ana.nextAck() == .ack(id: id, error: .wrongPhase))
        #expect(h.host.state.currentRound?.stops.count == 1)
    }

    @Test func snapshotsRedactedPerRecipient() async throws {
        let h = try Harness(stopsRequired: 2)
        let ana = try await h.join("Ana")
        let bea = try await h.join("Bea")
        await h.toWriting()
        ana.send(.stop(answers: ["Ana", "Anta"]))
        let own = await ana.nextSnapshot { $0.currentRound?.stops.count == 1 }
        let other = await bea.nextSnapshot { $0.currentRound?.stops.count == 1 }
        #expect(own?.currentRound?.answers[ana.playerID] == ["Ana", "Anta"])
        #expect(other?.currentRound?.answers[ana.playerID] == nil)
        #expect(h.host.localClient.state?.currentRound?.answers[ana.playerID] == nil)
        #expect(h.host.state.currentRound?.answers[ana.playerID] == ["Ana", "Anta"])
    }

    @Test func silentPlayerMarkedAwayAfterThreeSeconds() async throws {
        let h = try Harness(awayAfter: .seconds(3))
        let ana = try await h.join("Ana")
        await h.advance(seconds: 2)
        #expect(h.host.state.player(ana.playerID)?.presence == .present)
        await h.advance(seconds: 1)
        let snapshot = await ana.nextSnapshot { $0.player(ana.playerID)?.presence == .away }
        #expect(snapshot != nil)
        #expect(h.host.state.player(ana.playerID)?.presence == .away)
    }

    @Test func goingAwayMarksAwayImmediately() async throws {
        let h = try Harness()
        let ana = try await h.join("Ana")
        var changes = h.host.localClient.presenceChanges.makeAsyncIterator()
        ana.send(.goingAway)
        await waitUntil("Ana away") { h.host.state.player(ana.playerID)?.presence == .away }
        #expect(await changes.next() == PresenceChange(playerID: ana.playerID, kind: .wentAway))
    }

    @Test func returningPlayerMarkedPresent() async throws {
        let h = try Harness()
        let ana = try await h.join("Ana")
        ana.send(.goingAway)
        await waitUntil("Ana away") { h.host.state.player(ana.playerID)?.presence == .away }
        ana.send(.heartbeat)
        let snapshot = await ana.nextSnapshot { $0.player(ana.playerID)?.presence == .present }
        #expect(snapshot != nil)
    }

    @Test func ticksDriveRevealAndCountdown() async throws {
        let h = try Harness()
        let ana = try await h.join("Ana")
        h.host.localClient.send(.startGame)
        var phases = [h.host.state.phase]
        for _ in 0..<5 {
            await h.advance(seconds: 1)
            phases.append(h.host.state.phase)
        }
        #expect(phases == [.revealing(ticksRemaining: 2), .revealing(ticksRemaining: 1),
                           .countdown(secondsRemaining: 3), .countdown(secondsRemaining: 2),
                           .countdown(secondsRemaining: 1), .writing])
        #expect(await ana.nextSnapshot { $0.phase == .writing } != nil)
    }

    @Test func suspendStopsTicksSoCountdownPauses() async throws {
        let h = try Harness()
        let ana = try await h.join("Ana")
        h.host.localClient.send(.startGame)
        await h.advance(seconds: 3)
        #expect(h.host.state.phase == .countdown(secondsRemaining: 2))
        h.host.suspend()
        var received: WireMessage.Body?
        repeat { received = await ana.next() } while received != nil && received != .goingAway
        #expect(received == .goingAway)
        await waitUntil("loops stopped") { h.clock.sleeperCount == 0 }
        await h.clock.advance(by: .seconds(10))
        #expect(h.host.state.phase == .countdown(secondsRemaining: 2))
        h.host.resume()
        await h.advance(seconds: 1)
        #expect(h.host.state.phase == .countdown(secondsRemaining: 1))
    }

    @Test func stateIsPersistedOnEveryChange() async throws {
        let h = try Harness()
        await waitUntil("active game ref") {
            await h.store.loadActiveGame() == ActiveGameRef(gameID: h.host.state.gameID, role: .host, hostName: "Gui")
        }
        await waitUntil("initial save") { await h.store.loadHostGame() == h.host.state }
        _ = try await h.join("Ana")
        await waitUntil("join saved") { await h.store.loadHostGame() == h.host.state }
        h.host.localClient.send(.startGame)
        await waitUntil("start saved") { await h.store.loadHostGame() == h.host.state }
        await h.advance(seconds: 1)
        #expect(h.host.state.phase == .revealing(ticksRemaining: 1))
        await waitUntil("tick saved") { await h.store.loadHostGame() == h.host.state }
    }

    @Test func restoredHostKeepsGameIDAndMarksPlayersAway() async throws {
        var saved = try Harness.newGame()
        let anaID = UUID()
        var rng = SystemRandomNumberGenerator()
        try GameEngine.apply(.join(name: "Ana"), from: anaID, to: &saved, using: &rng)
        try GameEngine.apply(.startGame, from: saved.hostID, to: &saved, using: &rng)

        let h = try Harness(state: saved)
        #expect(h.host.state.gameID == saved.gameID)
        #expect(h.host.state.player(anaID)?.presence == .away)
        #expect(h.host.state.player(saved.hostID)?.presence == .present)
        #expect(await h.browse()?.advertisement.gameID == saved.gameID)

        let ana = try await h.connect(anaID, name: "Ana", gameID: saved.gameID)
        guard case .welcome(let state) = await ana.next() else { Issue.record("expected welcome"); return }
        #expect(state.player(anaID)?.presence == .present)
    }

    @Test func advertisementReflectsPlayerCountAndJoinable() async throws {
        let h = try Harness()
        let first = await h.browse()?.advertisement
        #expect(first?.playerCount == 1)
        #expect(first?.joinable == true)
        #expect(first?.hostName == "Gui")
        _ = try await h.join("Ana")
        #expect(await h.browse { $0.playerCount == 2 } != nil)
        h.host.localClient.send(.startGame)
        let started = await h.browse { !$0.joinable }
        #expect(started?.advertisement.playerCount == 2)
    }

    @Test func replacedConnectionClosesOld() async throws {
        let h = try Harness()
        let first = try await h.join("Ana")
        let second = try await h.connect(first.playerID, name: "Ana")
        guard case .welcome = await second.next() else { Issue.record("expected welcome"); return }
        #expect(await first.untilClosed())
        #expect(h.host.state.player(first.playerID)?.presence == .present)
        let id = second.send(.leave)
        #expect(await second.nextAck() == .ack(id: id, error: nil))
        #expect(h.host.state.player(first.playerID)?.presence == .left)
    }

    @Test func hostDraftSubmittedOnLock() async throws {
        let h = try Harness()
        let ana = try await h.join("Ana")
        await h.toWriting()
        h.host.localClient.saveDraft(["Gui", "Gato"])
        ana.send(.stop(answers: ["Ana", "Anta"]))
        await waitUntil("host answers submitted") {
            h.host.state.currentRound?.answers[h.hostID] == ["Gui", "Gato"]
        }
        #expect(h.host.localClient.frozenAnswers == ["Gui", "Gato"])
        #expect(h.host.state.phase == .scoring(categoryIndex: 0, completed: false))
    }

    @Test func endGameBroadcastsFinalSnapshotThenShutsDown() async throws {
        let h = try Harness()
        let ana = try await h.join("Ana")
        h.host.localClient.leave()
        #expect(await ana.nextSnapshot { $0.phase == .gameOver } != nil)
        #expect(h.host.localClient.hostStatus == .ended(.gameOver))
        await waitUntil("store cleared") {
            let game = await h.store.loadHostGame()
            let ref = await h.store.loadActiveGame()
            return game == nil && ref == nil
        }
        await waitUntil("linger timer") { h.clock.sleeperCount == 1 }
        await h.clock.advance(by: .seconds(5))
        #expect(await ana.untilClosed())
    }
}
