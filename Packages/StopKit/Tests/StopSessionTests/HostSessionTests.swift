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

    /// The ack for intent `id`, skipping acks for earlier intents.
    func ack(for id: UUID) async -> WireMessage.Body? {
        while let body = await nextAck() {
            if case .ack(id, _) = body { return body }
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
                 protocolVersion: Int = currentProtocolVersion, explicitRejoin: Bool = true) async throws -> RawClient {
        let game = try #require(await browse())
        let client = RawClient(net.connect(to: game.endpoint), playerID: id)
        client.send(.hello(playerID: id, name: name, gameID: gameID, lastVersion: nil, explicitRejoin: explicitRejoin),
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

    @Test func localClientCountsEveryError() throws {
        let h = try Harness()
        let client = h.host.localClient
        client.send(.startGame)
        client.send(.startGame)
        #expect(client.lastError == .notEnoughPlayers)
        #expect(client.errorCount == 2)
        client.send(.updateRoundSettings(stopsRequired: 1, allowGiveUp: true))
        #expect(client.lastError == nil)
        #expect(client.errorCount == 2)
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
        #expect(other?.currentRound?.answers[ana.playerID] == [])
        #expect(h.host.localClient.state?.currentRound?.answers[ana.playerID] == [])
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

    @Test func awayOnlyAfterRealSilence() async throws {
        let h = try Harness(awayAfter: .seconds(3))
        let ana = try await h.join("Ana")
        await waitUntil("loops armed") { h.clock.sleeperCount == 2 }
        await h.clock.advance(by: .milliseconds(900))
        let id = ana.send(.nextRound)
        #expect(await ana.nextAck() == .ack(id: id, error: .notHost))
        // Heartbeats at 1, 2 and 3 s: only 2.1 s of silence by then.
        await h.clock.advance(by: .milliseconds(100))
        await h.advance(seconds: 2)
        #expect(h.host.state.player(ana.playerID)?.presence == .present)
        await h.advance(seconds: 1)
        #expect(h.host.state.player(ana.playerID)?.presence == .away)
    }

    @Test func byeWithoutLeaveMarksAway() async throws {
        let h = try Harness()
        let ana = try await h.join("Ana")
        ana.send(.bye)
        await waitUntil("Ana away") { h.host.state.player(ana.playerID)?.presence == .away }
        #expect(await ana.untilClosed())
    }

    @Test func helloForAnotherPlayerUnmapsTheFirst() async throws {
        let h = try Harness()
        let ana = try await h.join("Ana")
        let beaID = UUID()
        ana.send(.hello(playerID: beaID, name: "Bea", gameID: nil, lastVersion: nil, explicitRejoin: true))
        await waitUntil("Bea present") { h.host.state.player(beaID)?.presence == .present }
        await waitUntil("Ana away") { h.host.state.player(ana.playerID)?.presence == .away }
        #expect(h.host.connectionPlayer[ana.connection.id] == beaID)
        #expect(h.host.playerConnection[ana.playerID] == nil)
    }

    @Test func noDraftSavedAfterShutdown() async throws {
        let h = try Harness()
        _ = try await h.join("Ana")
        await h.toWriting()
        h.host.localClient.saveDraft(["Gui", "Ga"])
        h.host.localClient.leave()
        h.host.localClient.saveDraft(["Gui", "Gato"])
        await h.clock.advance(by: .seconds(1))
        await waitUntil("store cleared") { await h.store.loadActiveGame() == nil }
        #expect(await h.store.loadDraft(gameID: h.host.state.gameID, round: 1) == nil)
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

    /// Moves the clock by `duration` once both loops (heartbeat and tick) are sleeping.
    private func step(_ h: Harness, _ duration: Duration) async {
        await waitUntil("2 sleepers") { h.clock.sleeperCount >= 2 }
        await h.clock.advance(by: duration)
        await waitUntil("2 sleepers") { h.clock.sleeperCount >= 2 }
    }

    @Test func revealLastsTwoFullTicksFromStartGame() async throws {
        let h = try Harness()
        _ = try await h.join("Ana")
        // Start mid-tick: without a restart, the first reveal tick would come 0.4 s later.
        await step(h, .milliseconds(600))
        h.host.localClient.send(.startGame)
        #expect(h.host.state.phase == .revealing(ticksRemaining: 2))
        await step(h, .milliseconds(900))
        #expect(h.host.state.phase == .revealing(ticksRemaining: 2))
        await step(h, .milliseconds(100))
        #expect(h.host.state.phase == .revealing(ticksRemaining: 1))
        await step(h, .seconds(1))
        #expect(h.host.state.phase == .countdown(secondsRemaining: 3))
    }

    @Test func completedCategoryWaitsForTheHostToMoveOn() async throws {
        let h = try Harness()
        let ana = try await h.join("Ana")
        await h.toWriting()
        ana.send(.stop(answers: ["Ana", "Anta"]))
        await waitUntil("scoring") { h.host.state.phase == .scoring(categoryIndex: 0, completed: false) }
        h.host.localClient.send(.setScore(round: 1, category: 0, points: 10, player: h.hostID))
        ana.send(.setScore(round: 1, category: 0, points: 10, player: ana.playerID))
        await waitUntil("completed") { h.host.state.phase == .scoring(categoryIndex: 0, completed: true) }
        // Ticks never move scoring on: everyone sees the scores until the host taps Next.
        await h.advance(seconds: 5)
        #expect(h.host.state.phase == .scoring(categoryIndex: 0, completed: true))
        // Ana can still correct her pick; only the host may advance.
        ana.send(.setScore(round: 1, category: 0, points: 5, player: ana.playerID))
        await waitUntil("corrected") { h.host.state.currentRound?.scores[ana.playerID]?[0] == 5 }
        let id = ana.send(.nextCategory(round: 1, category: 0))
        #expect(await ana.ack(for: id) == .ack(id: id, error: .notHost))
        #expect(h.host.state.phase == .scoring(categoryIndex: 0, completed: true))
        h.host.localClient.send(.nextCategory(round: 1, category: 0))
        #expect(h.host.state.phase == .scoring(categoryIndex: 1, completed: false))
        #expect(await ana.nextSnapshot { $0.phase == .scoring(categoryIndex: 1, completed: false) } != nil)
    }

    @Test func hostGoesBackFromResultsAndAPlayerCorrectsTheirScore() async throws {
        let h = try Harness()
        let ana = try await h.join("Ana")
        await h.toWriting()
        ana.send(.stop(answers: ["Ana", "Anta"]))
        await waitUntil("scoring") { h.host.state.phase == .scoring(categoryIndex: 0, completed: false) }
        for category in 0..<2 {
            h.host.localClient.send(.setScore(round: 1, category: category, points: 10, player: h.hostID))
            ana.send(.setScore(round: 1, category: category, points: 10, player: ana.playerID))
            await waitUntil("completed \(category)") {
                h.host.state.phase == .scoring(categoryIndex: category, completed: true)
            }
            h.host.localClient.send(.nextCategory(round: 1, category: category))
        }
        #expect(h.host.state.phase == .roundResults)
        // Only the host goes back.
        let id = ana.send(.previousCategory(round: 1, category: 2))
        #expect(await ana.ack(for: id) == .ack(id: id, error: .notHost))
        #expect(h.host.state.phase == .roundResults)
        h.host.localClient.send(.previousCategory(round: 1, category: 2))
        // A repeated tap is rejected by the category guard: it never moves twice.
        h.host.localClient.send(.previousCategory(round: 1, category: 2))
        #expect(h.host.state.phase == .scoring(categoryIndex: 1, completed: true))
        #expect(await ana.nextSnapshot { $0.phase == .scoring(categoryIndex: 1, completed: true) } != nil)
        ana.send(.setScore(round: 1, category: 1, points: 5, player: ana.playerID))
        await waitUntil("corrected") { h.host.state.currentRound?.scores[ana.playerID]?[1] == 5 }
        h.host.localClient.send(.nextCategory(round: 1, category: 1))
        #expect(h.host.state.phase == .roundResults)
        #expect(h.host.state.totals[ana.playerID] == 15)
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
        await waitUntil("old connection removed") { h.host.openConnections[first.connection.id] == nil }
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

    // MARK: Rejoining after leaving or removal (Ruling V)

    /// Ana joins and the game starts.
    private func startedWithAna(_ h: Harness) async throws -> RawClient {
        let ana = try await h.join("Ana")
        h.host.localClient.send(.startGame)
        await waitUntil("started") { h.host.state.currentRound != nil }
        return ana
    }

    @Test func removedPlayerReconnectingOnItsOwnIsShownTheStateButNotTakenBack() async throws {
        let h = try Harness()
        let ana = try await startedWithAna(h)
        h.host.localClient.send(.removePlayer(ana.playerID))
        await waitUntil("removed") { h.host.state.player(ana.playerID)?.presence == .removed }
        let version = h.host.state.version

        let again = try await h.connect(ana.playerID, name: "Ana", explicitRejoin: false)
        guard case .welcome(let state) = await again.next() else { Issue.record("expected welcome"); return }
        #expect(state.player(ana.playerID)?.presence == .removed)
        #expect(await again.untilClosed())
        #expect(h.host.state.player(ana.playerID)?.presence == .removed)
        #expect(h.host.state.version == version)
        #expect(h.host.connectionPlayer[again.connection.id] == nil)
    }

    @Test func removedPlayerRejoiningFromTheJoinListComesBackWithScore() async throws {
        let h = try Harness()
        let ana = try await startedWithAna(h)
        h.host.localClient.send(.removePlayer(ana.playerID))
        await waitUntil("removed") { h.host.state.player(ana.playerID)?.presence == .removed }
        let rounds = h.host.state.rounds

        let again = try await h.connect(ana.playerID, name: "Ana", explicitRejoin: true)
        guard case .welcome(let state) = await again.next() else { Issue.record("expected welcome"); return }
        #expect(state.player(ana.playerID)?.presence == .present)
        #expect(h.host.state.player(ana.playerID)?.presence == .present)
        // Back from the next round; what was recorded stays.
        #expect(h.host.state.currentRound?.participants.contains(ana.playerID) == false)
        #expect(h.host.state.rounds.map(\.scores) == rounds.map(\.scores))
    }

    @Test func leftPlayerRejoiningFromTheJoinListComesBack() async throws {
        let h = try Harness()
        let ana = try await startedWithAna(h)
        let id = ana.send(.leave)
        #expect(await ana.nextAck() == .ack(id: id, error: nil))
        ana.send(.bye)
        #expect(await ana.untilClosed())
        #expect(h.host.state.player(ana.playerID)?.presence == .left)

        let again = try await h.connect(ana.playerID, name: "Ana", explicitRejoin: true)
        guard case .welcome(let state) = await again.next() else { Issue.record("expected welcome"); return }
        #expect(state.player(ana.playerID)?.presence == .present)
        #expect(h.host.state.player(ana.playerID)?.presence == .present)
    }

    @Test func unknownPlayerRejoiningAStartedGameIsTurnedAway() async throws {
        let h = try Harness()
        _ = try await startedWithAna(h)
        let stranger = try await h.connect(name: "Bea", explicitRejoin: true)
        #expect(await stranger.next() == .rejected(.gameClosed))
        #expect(await stranger.untilClosed())
        #expect(h.host.state.player(stranger.playerID) == nil)
    }

    // MARK: Listener and local network

    @Test func localNetworkDenialIsSurfacedAndClearsWhenAllowed() async throws {
        let h = try Harness()
        #expect(!h.host.isLocalNetworkDenied)
        h.net.setLocalNetworkDenied(true)
        await waitUntil("denied") { h.host.isLocalNetworkDenied }
        h.net.setLocalNetworkDenied(false)
        await waitUntil("allowed") { !h.host.isLocalNetworkDenied }
    }

    @Test func hostStartedWhileDeniedReportsItAndRechecksOnResume() async throws {
        let net = InMemoryNetwork()
        net.setLocalNetworkDenied(true)
        let host = HostSession(state: try Harness.newGame(), factory: net, store: InMemoryGameStore(),
                               clock: TestClock())
        host.start()
        await waitUntil("denied") { host.isLocalNetworkDenied }
        host.suspend()
        net.setLocalNetworkDenied(false)
        host.resume()
        await waitUntil("allowed") { !host.isLocalNetworkDenied }
        host.shutdown()
    }

    @Test func failedListenerIsRestartedFromTheHeartbeatWithBackoff() async throws {
        let h = try Harness()
        let first = try #require(await h.browse())
        h.net.failListeners()
        await waitUntil("failure seen") { h.host.listenerFailed }
        // First restart after 1 s.
        await h.advance(seconds: 1)
        let second = try #require(await h.browse())
        #expect(second.endpoint != first.endpoint)
        #expect(second.advertisement.gameID == h.host.state.gameID)
        #expect(!h.host.listenerFailed)
        // Players can still join through the new listener.
        _ = try await h.join("Ana")
    }

    @Test func repeatedListenerFailuresBackOff() async throws {
        var timing = SessionTiming()
        timing.awayAfter = .seconds(3600)
        timing.listenerRestartBackoff = [.seconds(1), .seconds(3)]
        let net = InMemoryNetwork(), clock = TestClock()
        let host = HostSession(state: try Harness.newGame(), factory: net, store: InMemoryGameStore(), clock: clock,
                               timing: timing)
        host.start()
        net.failListeners()
        await waitUntil("failed") { host.listenerFailed }
        await waitUntil("loops") { clock.sleeperCount >= 2 }
        await clock.advance(by: .seconds(1))
        await waitUntil("restarted once") { !host.listenerFailed && host.listenerRestarts == 1 }
        net.failListeners()
        await waitUntil("failed again") { host.listenerFailed }
        // The second restart waits 3 s.
        for _ in 0..<2 {
            await waitUntil("loops") { clock.sleeperCount >= 2 }
            await clock.advance(by: .seconds(1))
        }
        await waitUntil("loops") { clock.sleeperCount >= 2 }
        #expect(host.listenerFailed)
        await clock.advance(by: .seconds(1))
        await waitUntil("restarted twice") { !host.listenerFailed && host.listenerRestarts == 2 }
        host.shutdown()
    }

    @Test func listenerIsNotRestartedAfterShutdown() async throws {
        let h = try Harness()
        h.host.shutdown()
        h.net.failListeners()
        await waitUntil("failure seen") { h.host.listenerFailed }
        await h.advance(seconds: 2, sleepers: 1)
        #expect(h.host.listenerFailed)
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
