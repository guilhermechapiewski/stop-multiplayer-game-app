import Foundation
import Network
import Synchronization
import Testing
@testable import StopNetworking

private func ad(players: Int = 1) -> Advertisement {
    Advertisement(gameID: UUID(), hostName: "Ana", playerCount: players, protocolVersion: 1, joinable: true)
}

/// Drains a stream in the background so tests can wait on its events with a deadline.
private final class Recorder<Event: Sendable>: Sendable {
    private let state = Mutex<(events: [Event], finished: Bool)>(([], false))

    init(_ stream: AsyncStream<Event>) {
        Task {
            for await event in stream { state.withLock { $0.events.append(event) } }
            state.withLock { $0.finished = true }
        }
    }

    var events: [Event] { state.withLock { $0.events } }
    var finished: Bool { state.withLock { $0.finished } }

    /// Waits until `condition` holds for the events so far; false on timeout.
    func wait(within timeout: Duration = .seconds(2), until condition: ([Event]) -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition(events) {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    func waitForFinish(within timeout: Duration = .seconds(2)) async -> Bool {
        await wait(within: timeout) { _ in finished }
    }
}

extension ListenerEvent {
    fileprivate var isReady: Bool { if case .ready = self { true } else { false } }
    fileprivate var connection: (any Connection)? { if case .connection(let c) = self { c } else { nil } }
}

/// Starts a non-advertising listener on loopback and returns it once ready, with its port.
private func loopbackListener(
    _ factory: NWTransportFactory
) async throws -> (NWTransportListener, Recorder<ListenerEvent>, NWEndpoint.Port) {
    let listener = try #require(factory.makeListener() as? NWTransportListener)
    let events = Recorder(listener.start(advertising: ad()))
    #expect(await events.wait { $0.contains { $0.isReady } })
    let port = try #require(listener.port)
    return (listener, events, port)
}

@Test(.timeLimit(.minutes(1))) func loopbackListenerAndConnectionExchangeFrames() async throws {
    let factory = NWTransportFactory(serviceType: "_stopgame._tcp", advertises: false)
    let (listener, listenerEvents, port) = try await loopbackListener(factory)
    defer { listener.stop() }

    let client = factory.connect(host: "127.0.0.1", port: port)
    let clientEvents = Recorder(client.events)
    client.start()
    #expect(await clientEvents.wait { $0 == [.ready] })

    #expect(await listenerEvents.wait { $0.contains { $0.connection != nil } })
    let server = try #require(listenerEvents.events.lazy.compactMap(\.connection).first)
    let serverEvents = Recorder(server.events)
    server.start()
    #expect(await serverEvents.wait { $0 == [.ready] })

    // 200 KB each way: far above one 64 KB read, so frames are reassembled from partial reads.
    let big = Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
    let small = Data("hello".utf8)
    client.send(small)
    client.send(big)
    client.send(Data())
    #expect(await serverEvents.wait { $0.count == 4 })
    #expect(serverEvents.events == [.ready, .message(small), .message(big), .message(Data())])

    let reply = Data(big.reversed())
    server.send(reply)
    server.send(small)
    #expect(await clientEvents.wait { $0.count == 3 })
    #expect(clientEvents.events == [.ready, .message(reply), .message(small)])

    // Graceful close: the closing end gets .closed at once; the peer gets pending data then .closed.
    let clock = ContinuousClock()
    let closedAt = clock.now
    client.send(Data("bye".utf8))
    client.close()
    client.send(Data("after close".utf8))  // no-op
    #expect(await clientEvents.waitForFinish())
    #expect(await serverEvents.waitForFinish())
    #expect(clock.now - closedAt < .seconds(2))
    #expect(clientEvents.events.last == .closed)
    #expect(clientEvents.events.filter { $0 == .closed }.count == 1)
    #expect(Array(serverEvents.events.suffix(2)) == [.message(Data("bye".utf8)), .closed])
    #expect(serverEvents.events.filter { $0 == .closed }.count == 1)
    server.close()  // already closed: no-op
}

@Test(.timeLimit(.minutes(1))) func serverCloseIsSeenByClient() async throws {
    let factory = NWTransportFactory(serviceType: "_stopgame._tcp", advertises: false)
    let (listener, listenerEvents, port) = try await loopbackListener(factory)
    defer { listener.stop() }
    let client = factory.connect(host: "127.0.0.1", port: port)
    let clientEvents = Recorder(client.events)
    client.start()
    #expect(await listenerEvents.wait { $0.contains { $0.connection != nil } })
    let server = try #require(listenerEvents.events.lazy.compactMap(\.connection).first)
    let serverEvents = Recorder(server.events)
    server.start()
    #expect(await serverEvents.wait { $0 == [.ready] })
    #expect(await clientEvents.wait { $0 == [.ready] })

    server.close()
    #expect(await serverEvents.waitForFinish())
    #expect(await clientEvents.waitForFinish())
    #expect(clientEvents.events == [.ready, .closed])
    #expect(serverEvents.events == [.ready, .closed])
}

@Test(.timeLimit(.minutes(1))) func connectToClosedPortEmitsOnlyClosed() async throws {
    let factory = NWTransportFactory(serviceType: "_stopgame._tcp", advertises: false)
    let (listener, _, port) = try await loopbackListener(factory)
    listener.stop()
    try await Task.sleep(for: .milliseconds(100))

    let client = factory.connect(host: "127.0.0.1", port: port)
    let events = Recorder(client.events)
    client.start()
    #expect(await events.waitForFinish())
    #expect(events.events == [.closed])
}

@Test(.timeLimit(.minutes(1))) func closeBeforeStartEmitsOnlyClosed() async throws {
    let factory = NWTransportFactory()
    let client = factory.connect(host: "127.0.0.1", port: 9)
    let events = Recorder(client.events)
    client.close()
    client.start()  // no-op after close
    #expect(await events.waitForFinish())
    #expect(events.events == [.closed])
}

/// Advertises over Bonjour, browses for it, sees a TXT update and connects through the discovered endpoint.
/// Needs mDNS and local network access; skipped on CI, and cancelled if the browser is denied or fails.
@Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), .timeLimit(.minutes(1)))
func browserFindsAdvertisedService() async throws {
    let factory = NWTransportFactory()
    let listener = factory.makeListener()
    var advertised = ad(players: 1)
    let listenerEvents = Recorder(listener.start(advertising: advertised))
    defer { listener.stop() }
    #expect(await listenerEvents.wait(within: .seconds(5)) { $0.contains { $0.isReady } })

    let browser = factory.makeBrowser()
    defer { browser.stop() }
    let browse = Recorder(browser.start())
    func game(where match: @escaping (Advertisement) -> Bool) async throws -> DiscoveredGame? {
        _ = await browse.wait(within: .seconds(10)) { events in
            events.contains { event in
                switch event {
                case .permissionDenied, .failed: true
                case .results(let games): games.contains { match($0.advertisement) }
                }
            }
        }
        for event in browse.events {
            switch event {
            case .permissionDenied: try Test.cancel("Local network access denied")
            case .failed: try Test.cancel("Bonjour browsing unavailable")
            case .results: break
            }
        }
        for case .results(let games) in browse.events.reversed() {
            if let found = games.first(where: { match($0.advertisement) }) { return found }
        }
        return nil
    }

    let first = try #require(try await game { $0 == advertised })
    advertised.playerCount = 3
    listener.update(advertised)
    let updated = try #require(try await game { $0 == advertised })
    #expect(updated.id == first.id)

    let client = factory.connect(to: updated.endpoint)
    let clientEvents = Recorder(client.events)
    client.start()
    #expect(await clientEvents.wait(within: .seconds(5)) { $0 == [.ready] })
    client.close()
}
