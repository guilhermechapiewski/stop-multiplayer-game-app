import Foundation
import StopNetworking
import StopSession
import StopTestSupport
import Testing
@testable import Stop

@MainActor
struct JoinModelTests {
    let network = InMemoryNetwork()

    private func advertise(_ host: String, protocolVersion: Int = currentProtocolVersion,
                           joinable: Bool = true) -> any Listener {
        let listener = network.makeListener()
        _ = listener.start(advertising: Advertisement(gameID: UUID(), hostName: host, playerCount: 2,
                                                      protocolVersion: protocolVersion, joinable: joinable))
        return listener
    }

    @Test func joinListsDiscoveredGames() async throws {
        let listener = advertise("Ana")
        defer { listener.stop() }
        let model = JoinModel(factory: network)

        model.start()
        defer { model.stop() }

        try await waitUntil { model.games.count == 1 }
        let game = try #require(model.games.first)
        #expect(game.advertisement.hostName == "Ana")
        #expect(JoinModel.availability(of: game) == .joinable)
        #expect(!model.permissionDenied)
    }

    @Test func gamesThatCannotBeJoinedSayWhy() async throws {
        let listeners = [advertise("Bia", joinable: false), advertise("Caio", protocolVersion: 99),
                         advertise("Ana")]
        defer { listeners.forEach { $0.stop() } }
        let model = JoinModel(factory: network)

        model.start()
        defer { model.stop() }

        try await waitUntil { model.games.count == 3 }
        #expect(model.games.map(\.advertisement.hostName) == ["Ana", "Bia", "Caio"])
        #expect(model.games.map(JoinModel.availability(of:)) == [.joinable, .inProgress, .updateRequired])
    }

    @Test func hostsWithTheSameNameGetSuffix() async throws {
        let listeners = [advertise("Ana"), advertise("Ana")]
        defer { listeners.forEach { $0.stop() } }
        let model = JoinModel(factory: network)

        model.start()
        defer { model.stop() }

        try await waitUntil { model.games.count == 2 }
        #expect(model.games.map(model.hostName(of:)) == ["Ana", "Ana 2"])
    }

    @Test func endedGamesDisappear() async throws {
        let listener = advertise("Ana")
        let model = JoinModel(factory: network)
        model.start()
        defer { model.stop() }
        try await waitUntil { model.games.count == 1 }

        listener.stop()

        try await waitUntil { model.games.isEmpty }
    }

    @Test func joinFlagsPermissionDenied() async throws {
        let model = JoinModel(factory: ScriptedBrowserFactory(events: [.permissionDenied]))

        model.start()
        defer { model.stop() }

        try await waitUntil { model.permissionDenied }
        #expect(model.games.isEmpty)
    }

    @Test func resultsAfterDenialClearTheFlag() async throws {
        let factory = ScriptedBrowserFactory(events: [.permissionDenied])
        let model = JoinModel(factory: factory)
        model.start()
        defer { model.stop() }
        try await waitUntil { model.permissionDenied }

        factory.browser.send(.results([]))

        try await waitUntil { !model.permissionDenied }
    }

    @Test(arguments: [[BrowserEvent.failed], []])
    func endedBrowserIsReplacedAfterDelay(events: [BrowserEvent]) async throws {
        let clock = TestClock()
        let factory = ScriptedBrowserFactory(browsers: [ScriptedBrowser(events: events, finishes: true)],
                                             fallback: network)
        let listener = advertise("Ana")
        defer { listener.stop() }
        let model = JoinModel(factory: factory, clock: clock)

        model.start()
        defer { model.stop() }

        try await waitUntil { clock.sleeperCount == 1 }
        #expect(factory.made == 1)
        await clock.advance(by: JoinModel.restartDelay)
        try await waitUntil { model.games.count == 1 }
        #expect(factory.made == 2)
    }

    @Test func refusedAccessIsRetriedWhenSceneBecomesActive() async throws {
        let clock = TestClock()
        let factory = ScriptedBrowserFactory(browsers: [ScriptedBrowser(events: [.permissionDenied], finishes: true)],
                                             fallback: network)
        let listener = advertise("Ana")
        defer { listener.stop() }
        let model = JoinModel(factory: factory, clock: clock)
        model.start()
        defer { model.stop() }
        try await waitUntil { model.permissionDenied }
        for _ in 0..<20 { await Task.yield() }
        #expect(clock.sleeperCount == 0)  // no polling while access is refused

        model.sceneBecameActive()

        try await waitUntil { model.games.count == 1 && !model.permissionDenied }
        #expect(factory.made == 2)
    }

    @Test func stopStopsBrowsing() async throws {
        let factory = ScriptedBrowserFactory(events: [])
        let model = JoinModel(factory: factory)
        model.start()
        model.stop()
        #expect(factory.browser.stopped)
    }
}

/// A transport whose browsers replay fixed events: `browsers` first, in order, then real browsers on `fallback`.
final class ScriptedBrowserFactory: TransportFactory, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [ScriptedBrowser]
    private var _made = 0
    let fallback: InMemoryNetwork
    /// The first scripted browser.
    let browser: ScriptedBrowser

    convenience init(events: [BrowserEvent]) {
        self.init(browsers: [ScriptedBrowser(events: events)])
    }

    init(browsers: [ScriptedBrowser], fallback: InMemoryNetwork = InMemoryNetwork()) {
        queue = browsers
        browser = browsers[0]
        self.fallback = fallback
    }

    /// How many browsers were made.
    var made: Int { lock.withLock { _made } }

    func makeListener() -> any Listener { fallback.makeListener() }
    func makeBrowser() -> any Browser {
        let next = lock.withLock { () -> ScriptedBrowser? in
            _made += 1
            return queue.isEmpty ? nil : queue.removeFirst()
        }
        return next ?? fallback.makeBrowser()
    }
    func connect(to endpoint: EndpointRef) -> any Connection { fallback.connect(to: endpoint) }
}

final class ScriptedBrowser: Browser, @unchecked Sendable {
    private let lock = NSLock()
    private let events: [BrowserEvent]
    private let finishes: Bool
    private var _stopped = false
    private var continuation: AsyncStream<BrowserEvent>.Continuation?

    /// With `finishes`, the stream ends after `events`, like `NWTransport`'s browser after a failure.
    init(events: [BrowserEvent], finishes: Bool = false) {
        self.events = events
        self.finishes = finishes
    }

    var stopped: Bool { lock.withLock { _stopped } }

    func start() -> AsyncStream<BrowserEvent> {
        AsyncStream { continuation in
            lock.withLock { self.continuation = continuation }
            for event in events { continuation.yield(event) }
            if finishes { continuation.finish() }
        }
    }

    func send(_ event: BrowserEvent) {
        _ = lock.withLock { continuation?.yield(event) }
    }

    func stop() {
        lock.withLock {
            _stopped = true
            continuation?.finish()
        }
    }
}
