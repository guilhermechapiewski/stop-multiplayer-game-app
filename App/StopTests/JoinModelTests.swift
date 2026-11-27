import Foundation
import StopNetworking
import StopSession
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

    @Test func stopStopsBrowsing() async throws {
        let factory = ScriptedBrowserFactory(events: [])
        let model = JoinModel(factory: factory)
        model.start()
        model.stop()
        #expect(factory.browser.stopped)
    }
}

/// A transport whose browser replays fixed events.
final class ScriptedBrowserFactory: TransportFactory {
    let browser: ScriptedBrowser

    init(events: [BrowserEvent]) { browser = ScriptedBrowser(events: events) }

    func makeListener() -> any Listener { InMemoryNetwork().makeListener() }
    func makeBrowser() -> any Browser { browser }
    func connect(to endpoint: EndpointRef) -> any Connection { InMemoryNetwork().connect(to: endpoint) }
}

final class ScriptedBrowser: Browser, @unchecked Sendable {
    private let lock = NSLock()
    private let events: [BrowserEvent]
    private var _stopped = false
    private var continuation: AsyncStream<BrowserEvent>.Continuation?

    init(events: [BrowserEvent]) { self.events = events }

    var stopped: Bool { lock.withLock { _stopped } }

    func start() -> AsyncStream<BrowserEvent> {
        AsyncStream { continuation in
            lock.withLock { self.continuation = continuation }
            for event in events { continuation.yield(event) }
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
