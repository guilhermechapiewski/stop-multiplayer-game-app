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

/// Like `waitUntil` but gives up quietly after ~100 ms.
@MainActor
private func poll(_ condition: () -> Bool) async {
    for _ in 0..<100 where !condition() { try? await Task.sleep(for: .milliseconds(1)) }
}

/// Advances the clock a second at a time (up to `seconds`) until `done` holds, letting timers re-arm between
/// steps. Timers that re-arm late only fire later, never earlier.
@MainActor
private func stepUntil(_ clock: TestClock, seconds: Int, _ done: () -> Bool) async {
    for _ in 0..<seconds where !done() {
        await waitUntil("a timer armed") { clock.sleeperCount >= 1 }
        await clock.advance(by: .seconds(1))
        for _ in 0..<20 where !done() { await Task.yield() }
    }
}

/// A real `HostSession` plus `ClientSession`s on one in-memory network and test clock.
@MainActor
private final class Harness {
    let net = InMemoryNetwork()
    let clock = TestClock()
    let hostStore = InMemoryGameStore()
    var host: HostSession
    var hostID: PlayerID { host.state.hostID }
    var gameID: UUID { host.state.gameID }

    init(stopsRequired: Int = 1) throws {
        let state = try GameEngine.newGame(
            gameID: UUID(), hostID: UUID(), hostName: "Gui",
            settings: GameSettings(categories: categories, stopsRequired: stopsRequired, allowGiveUp: true),
            language: .en)
        host = HostSession(state: state, factory: net, store: hostStore, clock: clock,
                           rng: SeededRNG(seed: 3))
        host.start()
    }

    func discovered() async throws -> DiscoveredGame {
        let browser = net.makeBrowser()
        defer { browser.stop() }
        for await event in browser.start() {
            if case .results(let games) = event, let game = games.first(where: { $0.advertisement.gameID == gameID }) {
                return game
            }
        }
        throw CancellationError()
    }

    /// A started client; waits until it is connected and the host sees it present.
    func join(_ name: String, id: PlayerID = UUID(), store: InMemoryGameStore = InMemoryGameStore(),
              target: ClientSession.Target? = nil, factory: (any TransportFactory)? = nil) async throws -> ClientSession {
        let resolved: ClientSession.Target
        if let target { resolved = target } else { resolved = .discovered(try await discovered()) }
        let client = ClientSession(profile: Profile(playerID: id, name: name, soundsEnabled: false),
                                   target: resolved, factory: factory ?? net, store: store, clock: clock)
        client.start()
        await waitUntil("\(name) connected") { client.hostStatus == .connected }
        await waitUntil("\(name) present") { host.state.player(id)?.presence == .present }
        return client
    }

    /// Advances the clock once `sleepers` timers are armed (host heartbeat and tick, client watchdog, plus
    /// whatever the test just started).
    func advance(by duration: Duration, sleepers: Int = 4) async {
        await waitUntil("\(sleepers) sleepers") { clock.sleeperCount >= sleepers }
        await clock.advance(by: duration)
    }

    /// Applies ticks directly, without moving the clock.
    func tick(_ count: Int = 1) {
        for _ in 0..<count { host.mutate { GameEngine.tick(&$0) } }
    }

    func toWriting() {
        host.localClient.send(.startGame)
        tick(5)
        #expect(host.state.phase == .writing)
    }

    /// Hides the host and drops every connection; `client` sees the host away.
    func disconnect(_ client: ClientSession) async throws {
        let endpoint = try await discovered().endpoint
        net.setReachable(false, listener: endpoint)
        net.dropAllConnections()
        await waitUntil("client sees host away") { client.hostStatus == .away }
        await waitUntil("host sees client away") {
            host.state.player(client.localPlayerID)?.presence == .away
        }
        hidden = endpoint
    }

    private var hidden: EndpointRef?

    /// Makes the host reachable again and moves the clock past any backoff.
    func reconnect(_ client: ClientSession) async {
        if let hidden { net.setReachable(true, listener: hidden) }
        for _ in 0..<5 where client.hostStatus != .connected {
            await clock.advance(by: .seconds(2))
            await poll { client.hostStatus == .connected }
        }
        await waitUntil("reconnected") { client.hostStatus == .connected }
    }
}

/// The in-memory network, except that its first browser reports permission denied and then fails.
private final class FailingFirstBrowser: TransportFactory, @unchecked Sendable {
    let net: InMemoryNetwork
    private var made = 0

    init(_ net: InMemoryNetwork) { self.net = net }

    func makeListener() -> any Listener { net.makeListener() }
    func connect(to endpoint: EndpointRef) -> any Connection { net.connect(to: endpoint) }
    func makeBrowser() -> any Browser {
        made += 1
        return made == 1 ? Failing() : net.makeBrowser()
    }

    private final class Failing: Browser {
        func start() -> AsyncStream<BrowserEvent> {
            AsyncStream { $0.yield(.permissionDenied); $0.yield(.failed); $0.finish() }
        }
        func stop() {}
    }
}

/// A scripted host: accepts connections and sends whatever the test says.
@MainActor
private final class FakeHost {
    let net: InMemoryNetwork
    let listener: any Listener
    private(set) var connections: [any Connection] = []
    private(set) var received: [WireMessage.Body] = []

    init(net: InMemoryNetwork, gameID: UUID) {
        self.net = net
        listener = net.makeListener()
        let events = listener.start(advertising: Advertisement(
            gameID: gameID, hostName: "Gui", playerCount: 1, protocolVersion: currentProtocolVersion, joinable: true))
        Task { [weak self] in
            for await event in events {
                guard case .connection(let connection) = event else { continue }
                self?.accept(connection)
            }
        }
    }

    private func accept(_ connection: any Connection) {
        connections.append(connection)
        connection.start()
        Task { [weak self] in
            for await event in connection.events {
                if case .message(let data) = event, let message = try? WireMessage.decode(data) {
                    self?.received.append(message.body)
                }
            }
        }
    }

    func send(_ body: WireMessage.Body) {
        guard let data = try? WireMessage(body: body).encoded() else { return }
        connections.last?.send(data)
    }
}

private func fakeState(gameID: UUID, me: PlayerID, version: Int, name: String = "Gui") -> GameState {
    let hostID = UUID()
    return GameState(
        gameID: gameID, hostID: hostID, version: version, language: .en,
        settings: GameSettings(categories: categories, stopsRequired: 1, allowGiveUp: true),
        players: [Player(id: hostID, name: name, presence: .present), Player(id: me, name: "Ana", presence: .present)],
        phase: .lobby, rounds: [], usedLetters: [])
}

@MainActor
private func fakeClient(_ net: InMemoryNetwork, clock: TestClock, gameID: UUID,
                        me: PlayerID = UUID()) async throws -> ClientSession {
    let browser = net.makeBrowser()
    var found: DiscoveredGame?
    for await event in browser.start() {
        if case .results(let games) = event, let game = games.first { found = game; break }
    }
    browser.stop()
    let client = ClientSession(profile: Profile(playerID: me, name: "Ana", soundsEnabled: false),
                               target: .discovered(try #require(found)), factory: net,
                               store: InMemoryGameStore(), clock: clock)
    client.start()
    return client
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ClientSessionTests {
    @Test func joinsAndMirrorsHostState() async throws {
        let h = try Harness()
        let store = InMemoryGameStore()
        let ana = try await h.join("Ana", store: store)
        #expect(ana.isHost == false)
        #expect(ana.state == h.host.state.redacted(for: ana.localPlayerID))
        await waitUntil("active game ref") {
            await store.loadActiveGame() == ActiveGameRef(gameID: h.gameID, role: .client, hostName: "Gui")
        }
        h.host.localClient.send(.updateRoundSettings(stopsRequired: 2, allowGiveUp: false))
        await waitUntil("settings mirrored") { ana.state?.settings.stopsRequired == 2 }
        #expect(ana.state == h.host.state.redacted(for: ana.localPlayerID))
    }

    @Test func staleSnapshotsIgnored() async throws {
        let net = InMemoryNetwork(), clock = TestClock(), gameID = UUID(), me = UUID()
        let fake = FakeHost(net: net, gameID: gameID)
        let ana = try await fakeClient(net, clock: clock, gameID: gameID, me: me)
        await waitUntil("hello") { !fake.received.isEmpty }
        fake.send(.welcome(fakeState(gameID: gameID, me: me, version: 5)))
        fake.send(.snapshot(fakeState(gameID: gameID, me: me, version: 3, name: "Old")))
        fake.send(.snapshot(fakeState(gameID: gameID, me: me, version: 6, name: "New")))
        await waitUntil("v6 applied") { ana.state?.version == 6 }
        fake.send(.snapshot(fakeState(gameID: gameID, me: me, version: 6, name: "Same")))
        fake.send(.snapshot(fakeState(gameID: gameID, me: me, version: 4, name: "Older")))
        fake.send(.heartbeat)
        fake.send(.snapshot(fakeState(gameID: gameID, me: me, version: 7, name: "Newest")))
        await waitUntil("v7 applied") { ana.state?.version == 7 }
        #expect(ana.state?.players.first?.name == "Newest")
        // A different game replaces the state whatever its version.
        let other = UUID()
        fake.send(.snapshot(fakeState(gameID: other, me: me, version: 1)))
        await waitUntil("new game applied") { ana.state?.gameID == other }
    }

    @Test func intentQueuedWhileDisconnectedIsSentAfterReconnect() async throws {
        let h = try Harness(stopsRequired: 2)
        let ana = try await h.join("Ana")
        h.toWriting()
        await waitUntil("writing") { ana.state?.phase == .writing }
        try await h.disconnect(ana)
        ana.send(.stop(answers: ["Ana", "Anta"]))
        #expect(ana.frozenAnswers == ["Ana", "Anta"])
        #expect(h.host.state.currentRound?.stops.isEmpty == true)
        await h.reconnect(ana)
        await waitUntil("stop applied") { h.host.state.currentRound?.stops.count == 1 }
        #expect(h.host.state.currentRound?.answers[ana.localPlayerID] == ["Ana", "Anta"])
        await waitUntil("acked") { ana.pendingIntentCount == 0 }
        #expect(ana.lastError == nil)
    }

    @Test func rejectedStopIsNotRetriedAndUnfreezes() async throws {
        let h = try Harness(stopsRequired: 2)
        let ana = try await h.join("Ana")
        h.toWriting()
        await waitUntil("writing") { ana.state?.phase == .writing }
        ana.send(.stop(answers: ["Ana", " "]))
        #expect(ana.frozenAnswers == ["Ana", " "])
        await waitUntil("rejected") { ana.lastError == .answersIncomplete }
        #expect(ana.frozenAnswers == nil)
        #expect(ana.pendingIntentCount == 0)
        // A reconnect doesn't resend it.
        h.net.dropAllConnections()
        await h.reconnect(ana)
        #expect(h.host.state.currentRound?.stops.isEmpty == true)
        #expect(ana.pendingIntentCount == 0)
    }

    @Test func racingStopAfterLockIsAckedAndKeepsLockFreeze() async throws {
        let h = try Harness()
        let ana = try await h.join("Ana")
        h.toWriting()
        await waitUntil("writing") { ana.state?.phase == .writing }
        ana.saveDraft(["Ana", "Anta"])
        h.net.setLatency(.milliseconds(50))
        h.host.localClient.send(.stop(answers: ["Gui", "Gato"]))
        ana.send(.stop(answers: ["Ana", "Anta"]))
        await waitUntil("racing stop rejected") { ana.lastError == .wrongPhase }
        await waitUntil("answers submitted") {
            h.host.state.currentRound?.answers[ana.localPlayerID] == ["Ana", "Anta"]
        }
        #expect(ana.frozenAnswers == ["Ana", "Anta"])
        #expect(h.host.state.currentRound?.stops.count == 1)
        await waitUntil("queue empty") { ana.pendingIntentCount == 0 }
    }

    @Test func duplicateDeliveryDoesNotDoubleApply() async throws {
        let h = try Harness(stopsRequired: 2)
        let ana = try await h.join("Ana")
        h.toWriting()
        await waitUntil("writing") { ana.state?.phase == .writing }
        let before = h.host.state.version
        h.net.duplicateNextMessage()
        ana.send(.stop(answers: ["Ana", "Anta"]))
        await waitUntil("acked") { ana.pendingIntentCount == 0 }
        await waitUntil("snapshot") { ana.state?.currentRound?.stops.count == 1 }
        #expect(h.host.state.version == before + 1)
        #expect(h.host.state.currentRound?.stops.count == 1)
        #expect(ana.lastError == nil)
    }

    @Test func hostSilenceMarksHostAwayThenMayBeGone() async throws {
        let net = InMemoryNetwork(), clock = TestClock(), gameID = UUID(), me = UUID()
        let fake = FakeHost(net: net, gameID: gameID)
        let ana = try await fakeClient(net, clock: clock, gameID: gameID, me: me)
        await waitUntil("hello") { !fake.received.isEmpty }
        fake.send(.welcome(fakeState(gameID: gameID, me: me, version: 1)))
        await waitUntil("connected") { ana.hostStatus == .connected }
        func advance(_ seconds: Int) async {
            for _ in 0..<seconds {
                await waitUntil("watchdog armed") { clock.sleeperCount == 1 }
                await clock.advance(by: .seconds(1))
            }
            await waitUntil("watchdog armed") { clock.sleeperCount == 1 }
        }
        await advance(2)
        #expect(ana.hostStatus == .connected)
        await waitUntil("2 heartbeats") { fake.received.filter { $0 == .heartbeat }.count == 2 }
        await advance(1)
        #expect(ana.hostStatus == .away)
        // From 6 s of silence on, the client keeps recycling connections the host never welcomes; that doesn't
        // restart the 120 s "may be gone" timer.
        await stepUntil(clock, seconds: 119) { false }
        #expect(ana.hostStatus == .away)
        #expect(fake.connections.count > 2)
        await stepUntil(clock, seconds: 10) { ana.hostStatus == .mayBeGone }
        await waitUntil("may be gone") { ana.hostStatus == .mayBeGone }
    }

    @Test func silentHalfOpenHostConnectionIsDroppedAndReconnected() async throws {
        let h = try Harness()
        let store = InMemoryGameStore()
        let ana = try await h.join("Ana", store: store)
        h.toWriting()
        await waitUntil("writing") { ana.state?.phase == .writing }
        // The host app is suspended and comes back on a new listener; the old socket stays open but carries
        // nothing (its messages, the goingAway included, never arrive).
        h.net.setLatency(.seconds(3600))
        h.host.suspend()
        h.host.listener?.stop()
        h.net.setLatency(.zero)
        let restored = HostSession(state: h.host.state, factory: h.net, store: h.hostStore, clock: h.clock)
        restored.start()
        h.host = restored
        await stepUntil(h.clock, seconds: 3) { false }
        #expect(ana.hostStatus == .away)
        // While away, intents queue and drafts keep saving.
        ana.send(.stop(answers: ["Ana", "Anta"]))
        ana.saveDraft(["Ana", "Anta"])
        await stepUntil(h.clock, seconds: 2) { false }
        await waitUntil("draft saved") { await store.loadDraft(gameID: h.gameID, round: 1) == ["Ana", "Anta"] }
        #expect(ana.hostStatus == .away)
        await stepUntil(h.clock, seconds: 5) { ana.hostStatus == .connected }
        await waitUntil("reconnected") { ana.hostStatus == .connected }
        await waitUntil("present on restored host") {
            restored.state.player(ana.localPlayerID)?.presence == .present
        }
        await waitUntil("queued stop applied") { restored.state.currentRound?.stops.count == 1 }
    }

    @Test func goingAwayFromHostShowsAwayImmediately() async throws {
        let h = try Harness()
        let ana = try await h.join("Ana")
        h.host.suspend()
        await waitUntil("away") { ana.hostStatus == .away }
        h.host.resume()
        await waitUntil("back") { ana.hostStatus == .connected }
    }

    @Test func reconnectsWithBackoffAfterDrop() async throws {
        let h = try Harness()
        let ana = try await h.join("Ana")
        let endpoint = try await h.discovered().endpoint
        h.net.setReachable(false, listener: endpoint)
        h.net.dropAllConnections()
        await waitUntil("away") { ana.hostStatus == .away }
        #expect(ana.reconnectAttempts == 0)
        // Backoff 0.25 s, then 0.5 s: each failed attempt waits longer.
        await h.advance(by: .milliseconds(200))
        #expect(ana.reconnectAttempts == 0)
        await h.advance(by: .milliseconds(50))
        await waitUntil("first attempt") { ana.reconnectAttempts == 1 }
        await h.advance(by: .milliseconds(400))
        #expect(ana.reconnectAttempts == 1)
        await h.advance(by: .milliseconds(100))
        await waitUntil("second attempt") { ana.reconnectAttempts == 2 }
        h.net.setReachable(true, listener: endpoint)
        await h.advance(by: .seconds(1))
        await waitUntil("reconnected") { ana.hostStatus == .connected }
        #expect(ana.reconnectAttempts == 0)
        await waitUntil("present") { h.host.state.player(ana.localPlayerID)?.presence == .present }
    }

    @Test func rejoinsByGameIDAfterHostRestart() async throws {
        let h = try Harness()
        let ana = try await h.join("Ana")
        let oldEndpoint = try await h.discovered().endpoint
        // The host app dies: its listener and connections go away; a restored session starts elsewhere.
        h.host.suspend()
        h.host.listener?.stop()
        h.net.dropAllConnections()
        await waitUntil("away") { ana.hostStatus == .away }
        let restored = HostSession(state: h.host.state, factory: h.net, store: h.hostStore, clock: h.clock)
        restored.start()
        h.host = restored
        #expect(try await h.discovered().endpoint != oldEndpoint)
        await h.reconnect(ana)
        await waitUntil("present on restored host") {
            restored.state.player(ana.localPlayerID)?.presence == .present
        }
    }

    @Test func failedBrowserIsRestartedAndFindsRestartedHost() async throws {
        let h = try Harness()
        let factory = FailingFirstBrowser(h.net)
        let ana = try await h.join("Ana", factory: factory)
        h.host.suspend()
        h.host.listener?.stop()
        h.net.dropAllConnections()
        await waitUntil("denied surfaced") { ana.isLocalNetworkDenied }
        let restored = HostSession(state: h.host.state, factory: h.net, store: h.hostStore, clock: h.clock)
        restored.start()
        h.host = restored
        await h.reconnect(ana)
        #expect(ana.isLocalNetworkDenied == false)
        await waitUntil("present on restored host") {
            restored.state.player(ana.localPlayerID)?.presence == .present
        }
    }

    @Test func rejoinWithNoHostReachesMayBeGone() async throws {
        let net = InMemoryNetwork(), clock = TestClock()
        let ana = ClientSession(profile: Profile(playerID: UUID(), name: "Ana", soundsEnabled: false),
                                target: .rejoin(gameID: UUID()), factory: net, store: InMemoryGameStore(),
                                clock: clock)
        ana.start()
        await stepUntil(clock, seconds: 119) { false }
        #expect(ana.hostStatus == .connecting)
        await stepUntil(clock, seconds: 5) { ana.hostStatus == .mayBeGone }
        await waitUntil("may be gone") { ana.hostStatus == .mayBeGone }
        ana.stop()
    }

    @Test func resentStopAlreadyAppliedByRestartedHostCountsAsSuccess() async throws {
        let h = try Harness(stopsRequired: 2)
        let ana = try await h.join("Ana")
        h.toWriting()
        await waitUntil("writing") { ana.state?.phase == .writing }
        try await h.disconnect(ana)
        let answers = ["Ana", "Anta"]
        ana.send(.stop(answers: answers))
        // The host applied it earlier, but its intent log (and the ack) were lost.
        #expect(h.host.apply(.stop(answers: answers), from: ana.localPlayerID) == nil)
        await h.reconnect(ana)
        await waitUntil("acked") { ana.pendingIntentCount == 0 }
        #expect(ana.lastError == nil)
        #expect(ana.frozenAnswers == answers)
        #expect(h.host.state.currentRound?.stops.count == 1)
    }

    @Test func welcomeFromBeforeTheLockUnfreezes() async throws {
        let h = try Harness()
        let ana = try await h.join("Ana")
        h.toWriting()
        await waitUntil("writing") { ana.state?.phase == .writing }
        let beforeLock = h.host.state
        ana.saveDraft(["Ana", "Anta"])
        h.host.localClient.send(.stop(answers: ["Gui", "Gato"]))
        await waitUntil("frozen at lock") { ana.frozenAnswers == ["Ana", "Anta"] }
        // The host restarts from a save taken before the lock.
        h.host.suspend()
        h.host.listener?.stop()
        h.net.dropAllConnections()
        await waitUntil("away") { ana.hostStatus == .away }
        let restored = HostSession(state: beforeLock, factory: h.net, store: h.hostStore, clock: h.clock)
        restored.start()
        h.host = restored
        await h.reconnect(ana)
        await waitUntil("writing again") { ana.state?.phase == .writing }
        #expect(ana.frozenAnswers == nil)
        // The next lock submits again.
        restored.localClient.send(.stop(answers: ["Gui", "Gato"]))
        await waitUntil("submitted to restored host") {
            restored.state.currentRound?.answers[ana.localPlayerID] == ["Ana", "Anta"]
        }
    }

    @Test func successfulAckClearsLastErrorAndStopDisconnects() async throws {
        let h = try Harness()
        let ana = try await h.join("Ana")
        ana.send(.nextRound)
        await waitUntil("rejected") { ana.lastError == .notHost }
        ana.send(.leave)
        await waitUntil("cleared") { ana.lastError == nil }
        ana.stop()
        #expect(ana.hostStatus == .connecting)
    }

    @Test func lockFreezesDraftAndSubmits() async throws {
        let h = try Harness()
        let ana = try await h.join("Ana")
        h.toWriting()
        await waitUntil("writing") { ana.state?.phase == .writing }
        ana.saveDraft(["Ana", "Anta"])
        h.host.localClient.send(.stop(answers: ["Gui", "Gato"]))
        await waitUntil("submitted") { h.host.state.currentRound?.answers[ana.localPlayerID] == ["Ana", "Anta"] }
        #expect(ana.frozenAnswers == ["Ana", "Anta"])
        #expect(h.host.state.phase == .scoring(categoryIndex: 0, completed: false))
        #expect(ana.lastError == nil)
    }

    @Test func disconnectedClientSubmitsDraftOnReconnectDuringScoring() async throws {
        let h = try Harness()
        let ana = try await h.join("Ana")
        h.toWriting()
        await waitUntil("writing") { ana.state?.phase == .writing }
        ana.saveDraft(["Ana", "Anta"])
        try await h.disconnect(ana)
        h.host.localClient.send(.stop(answers: ["Gui", "Gato"]))
        #expect(h.host.state.phase == .scoring(categoryIndex: 0, completed: false))
        h.host.localClient.send(.setScore(round: 1, category: 0, points: 10, player: h.hostID))
        h.tick()
        #expect(h.host.state.phase == .scoring(categoryIndex: 1, completed: false))
        await h.reconnect(ana)
        await waitUntil("late answers") { h.host.state.currentRound?.answers[ana.localPlayerID] == ["Ana", "Anta"] }
        #expect(h.host.state.currentRound?.scores[ana.localPlayerID] == [0, nil])
        #expect(ana.frozenAnswers == ["Ana", "Anta"])
    }

    @Test func draftRestoredAfterAppKill() async throws {
        let h = try Harness()
        let store = InMemoryGameStore()
        let anaID = UUID()
        let first = try await h.join("Ana", id: anaID, store: store)
        h.toWriting()
        await waitUntil("writing") { first.state?.phase == .writing }
        first.saveDraft(["Ana", "An"])
        await h.advance(by: .milliseconds(300))
        await waitUntil("draft saved") { await store.loadDraft(gameID: h.gameID, round: 1) == ["Ana", "An"] }
        first.stop()
        await waitUntil("host sees Ana away") { h.host.state.player(anaID)?.presence == .away }
        let ref = try #require(await store.loadActiveGame())
        #expect(ref.role == .client && ref.gameID == h.gameID)

        let relaunched = try await h.join("Ana", id: anaID, store: store, target: .rejoin(gameID: ref.gameID))
        #expect(relaunched.state?.phase == .writing)
        #expect(await relaunched.draft() == ["Ana", "An"])
    }

    @Test func previousRoundDraftNeverSubmitted() async throws {
        let h = try Harness()
        let ana = try await h.join("Ana")
        h.toWriting()
        await waitUntil("writing") { ana.state?.phase == .writing }
        ana.saveDraft(["Ana", "Anta"])
        await h.advance(by: .milliseconds(300))
        try await h.disconnect(ana)
        // Round 1 finishes and round 2 locks while Ana is away.
        h.host.localClient.send(.stop(answers: ["Gui", "Gato"]))
        for category in 0..<2 {
            h.host.localClient.send(.setScore(round: 1, category: category, points: 10, player: h.hostID))
            h.tick()
        }
        #expect(h.host.state.phase == .roundResults)
        h.host.localClient.send(.nextRound)
        h.tick(5)
        h.host.localClient.send(.stop(answers: ["Bia", "Boi"]))
        #expect(h.host.state.currentRound?.number == 2)
        await h.reconnect(ana)
        await waitUntil("round 2 answers") { h.host.state.currentRound?.answers[ana.localPlayerID] != nil }
        #expect(h.host.state.currentRound?.answers[ana.localPlayerID] == ["", ""])
        #expect(h.host.state.rounds[0].answers[ana.localPlayerID] == nil)
        #expect(ana.frozenAnswers == ["", ""])
        #expect(await ana.draft() == nil)
    }

    @Test func presenceChangesEmittedForOtherPlayers() async throws {
        let h = try Harness()
        let ana = try await h.join("Ana")
        let bob = try await h.join("Bob")
        var changes = ana.presenceChanges.makeAsyncIterator()
        bob.stop()
        #expect(await changes.next() == PresenceChange(playerID: bob.localPlayerID, kind: .wentAway))
        bob.start()
        #expect(await changes.next() == PresenceChange(playerID: bob.localPlayerID, kind: .returned))
    }

    @Test func versionMismatchEndsWithoutReconnect() async throws {
        let net = InMemoryNetwork(), clock = TestClock(), gameID = UUID()
        let fake = FakeHost(net: net, gameID: gameID)
        let ana = try await fakeClient(net, clock: clock, gameID: gameID)
        await waitUntil("hello") { !fake.received.isEmpty }
        fake.send(.rejected(.versionMismatch))
        await waitUntil("ended") { ana.hostStatus == .ended(.versionMismatch) }
        fake.connections.last?.close()
        await clock.advance(by: .seconds(10))
        #expect(fake.connections.count == 1)
        #expect(clock.sleeperCount == 0)
    }

    @Test func removedPlayerEnds() async throws {
        let h = try Harness()
        let store = InMemoryGameStore()
        let ana = try await h.join("Ana", store: store)
        await waitUntil("active game ref") { await store.loadActiveGame() != nil }
        h.host.localClient.send(.removePlayer(ana.localPlayerID))
        await waitUntil("ended") { ana.hostStatus == .ended(.removed) }
        await waitUntil("ref cleared") { await store.loadActiveGame() == nil }
    }

    @Test func gameOverClearsActiveGame() async throws {
        let h = try Harness()
        let store = InMemoryGameStore()
        let ana = try await h.join("Ana", store: store)
        h.toWriting()
        await waitUntil("writing") { ana.state?.phase == .writing }
        ana.saveDraft(["Ana", "Anta"])
        await h.advance(by: .milliseconds(300))
        await waitUntil("draft saved") { await store.loadDraft(gameID: h.gameID, round: 1) != nil }
        h.host.localClient.leave()
        await waitUntil("ended") { ana.hostStatus == .ended(.gameOver) }
        await waitUntil("cleared") {
            let ref = await store.loadActiveGame()
            let draft = await store.loadDraft(gameID: h.gameID, round: 1)
            return ref == nil && draft == nil
        }
        ana.saveDraft(["late"])
        await h.clock.advance(by: .seconds(1))
        #expect(await store.loadDraft(gameID: h.gameID, round: 1) == nil)
    }

    @Test func leaveSendsLeaveThenByeAndEnds() async throws {
        let h = try Harness()
        let store = InMemoryGameStore()
        let ana = try await h.join("Ana", store: store)
        ana.leave()
        await waitUntil("left on host") { h.host.state.player(ana.localPlayerID)?.presence == .left }
        await waitUntil("ended") { ana.hostStatus == .ended(.leftGame) }
        await waitUntil("ref cleared") { await store.loadActiveGame() == nil }
    }
}
