import Foundation
import Testing
@testable import StopNetworking

private func ad(_ name: String = "Ana", players: Int = 1, joinable: Bool = true) -> Advertisement {
    Advertisement(gameID: UUID(), hostName: name, playerCount: players, protocolVersion: 1, joinable: joinable)
}

/// Pulls browser events until `predicate` matches a results list.
private func waitForResults(
    _ iterator: inout AsyncStream<BrowserEvent>.Iterator,
    where predicate: ([DiscoveredGame]) -> Bool
) async -> [DiscoveredGame]? {
    while let event = await iterator.next() {
        if case .results(let games) = event, predicate(games) { return games }
    }
    return nil
}

/// Starts a listener, browses for it, connects and starts both ends; returns them once both are ready.
private func connectedPair(
    on net: InMemoryNetwork
) async throws -> (client: any Connection, server: any Connection, endpoint: EndpointRef) {
    let listener = net.makeListener()
    var listenerEvents = listener.start(advertising: ad()).makeAsyncIterator()
    #expect(await listenerEvents.next()?.isReady == true)

    let browser = net.makeBrowser()
    var browse = browser.start().makeAsyncIterator()
    let games = try #require(await waitForResults(&browse) { !$0.isEmpty })
    browser.stop()

    let client = net.connect(to: games[0].endpoint)
    var clientEvents = client.events.makeAsyncIterator()
    client.start()
    #expect(await clientEvents.next() == .ready)

    guard case .connection(let server) = await listenerEvents.next() else {
        Issue.record("expected an incoming connection")
        throw CancellationError()
    }
    server.start()
    return (client, server, games[0].endpoint)
}

extension ListenerEvent {
    fileprivate var isReady: Bool { if case .ready = self { true } else { false } }
}

@Test func txtRecordRoundTrip() throws {
    let original = Advertisement(
        gameID: UUID(), hostName: "Zé da Silva", playerCount: 5, protocolVersion: 1, joinable: false)
    let txt = original.txtRecord()
    #expect(Set(txt.keys) == ["g", "h", "n", "v", "j"])
    #expect(Advertisement(txtRecord: txt) == original)
    var missing = txt
    missing["g"] = nil
    #expect(Advertisement(txtRecord: missing) == nil)
    var garbled = txt
    garbled["n"] = "lots"
    #expect(Advertisement(txtRecord: garbled) == nil)
}

@Test(.timeLimit(.minutes(1))) func inMemoryBrowseSeesAdvertisementAndUpdates() async throws {
    let net = InMemoryNetwork()
    let browser = net.makeBrowser()
    var browse = browser.start().makeAsyncIterator()
    #expect(await waitForResults(&browse) { $0.isEmpty } != nil)

    let listener = net.makeListener()
    let first = ad("Ana", players: 1)
    _ = listener.start(advertising: first)
    let seen = try #require(await waitForResults(&browse) { !$0.isEmpty })
    #expect(seen.map(\.advertisement) == [first])

    var updated = first
    updated.playerCount = 3
    updated.joinable = false
    listener.update(updated)
    let after = try #require(await waitForResults(&browse) { $0.first?.advertisement == updated })
    #expect(after.count == 1)
    #expect(after[0].id == seen[0].id)
    #expect(after[0].endpoint == seen[0].endpoint)

    listener.stop()
    #expect(await waitForResults(&browse) { $0.isEmpty } != nil)
}

@Test(.timeLimit(.minutes(1))) func inMemoryMessagesArriveInOrder() async throws {
    let net = InMemoryNetwork()
    let (client, server, _) = try await connectedPair(on: net)
    var serverEvents = server.events.makeAsyncIterator()
    #expect(await serverEvents.next() == .ready)

    let messages = (0..<200).map { Data("m\($0)".utf8) }
    for message in messages { client.send(message) }
    var received: [Data] = []
    for _ in messages {
        if case .message(let data) = await serverEvents.next() { received.append(data) }
    }
    #expect(received == messages)

    // With latency, still in order, and replies flow the other way.
    net.setLatency(.milliseconds(5))
    var clientEvents = client.events.makeAsyncIterator()
    let replies = (0..<20).map { Data("r\($0)".utf8) }
    for reply in replies { server.send(reply) }
    var gotReplies: [Data] = []
    for _ in replies {
        if case .message(let data) = await clientEvents.next() { gotReplies.append(data) }
    }
    #expect(gotReplies == replies)
}

@Test(.timeLimit(.minutes(1))) func latencyDelaysDelivery() async throws {
    let net = InMemoryNetwork()
    let (client, server, _) = try await connectedPair(on: net)
    var serverEvents = server.events.makeAsyncIterator()
    #expect(await serverEvents.next() == .ready)
    net.setLatency(.milliseconds(50))
    let clock = ContinuousClock()
    let sentAt = clock.now
    client.send(Data("x".utf8))
    #expect(await serverEvents.next() == .message(Data("x".utf8)))
    #expect(clock.now - sentAt >= .milliseconds(50))
}

@Test(.timeLimit(.minutes(1))) func severClosesBothEnds() async throws {
    let net = InMemoryNetwork()
    let (client, server, _) = try await connectedPair(on: net)
    #expect(client.id == server.id)
    var clientEvents = client.events.makeAsyncIterator()
    var serverEvents = server.events.makeAsyncIterator()
    #expect(await serverEvents.next() == .ready)

    net.severClient(server.id)
    #expect(await clientEvents.next() == .closed)
    #expect(await serverEvents.next() == .closed)
    // .closed is emitted exactly once: the streams finish afterwards.
    #expect(await clientEvents.next() == nil)
    #expect(await serverEvents.next() == nil)
    // Sending after close is a no-op.
    client.send(Data("late".utf8))
    server.close()
}

@Test(.timeLimit(.minutes(1))) func closeDeliversPendingMessagesThenClosedToPeer() async throws {
    let net = InMemoryNetwork()
    let (client, server, _) = try await connectedPair(on: net)
    var clientEvents = client.events.makeAsyncIterator()
    var serverEvents = server.events.makeAsyncIterator()
    #expect(await serverEvents.next() == .ready)

    client.send(Data("bye".utf8))
    client.close()
    #expect(await clientEvents.next() == .closed)
    #expect(await clientEvents.next() == nil)
    #expect(await serverEvents.next() == .message(Data("bye".utf8)))
    #expect(await serverEvents.next() == .closed)
    #expect(await serverEvents.next() == nil)
}

@Test(.timeLimit(.minutes(1))) func dropAllConnectionsClosesEveryLinkToTheEndpoint() async throws {
    let net = InMemoryNetwork()
    let (client, server, endpoint) = try await connectedPair(on: net)
    var clientEvents = client.events.makeAsyncIterator()
    var serverEvents = server.events.makeAsyncIterator()
    #expect(await serverEvents.next() == .ready)

    net.dropAllConnections(of: endpoint)
    #expect(await clientEvents.next() == .closed)
    #expect(await serverEvents.next() == .closed)
}

@Test(.timeLimit(.minutes(1))) func unreachableListenerHiddenAndRefusesConnections() async throws {
    let net = InMemoryNetwork()
    let listener = net.makeListener()
    _ = listener.start(advertising: ad())
    let browser = net.makeBrowser()
    var browse = browser.start().makeAsyncIterator()
    let games = try #require(await waitForResults(&browse) { !$0.isEmpty })
    let endpoint = games[0].endpoint

    net.setReachable(false, listener: endpoint)
    #expect(await waitForResults(&browse) { $0.isEmpty } != nil)

    let refused = net.connect(to: endpoint)
    var refusedEvents = refused.events.makeAsyncIterator()
    refused.start()
    #expect(await refusedEvents.next() == .closed)
    #expect(await refusedEvents.next() == nil)

    net.setReachable(true, listener: endpoint)
    #expect(await waitForResults(&browse) { $0.map(\.endpoint) == [endpoint] } != nil)
    let accepted = net.connect(to: endpoint)
    var acceptedEvents = accepted.events.makeAsyncIterator()
    accepted.start()
    #expect(await acceptedEvents.next() == .ready)
}

@Test(.timeLimit(.minutes(1))) func duplicateNextMessageDeliversTwice() async throws {
    let net = InMemoryNetwork()
    let (client, server, _) = try await connectedPair(on: net)
    var serverEvents = server.events.makeAsyncIterator()
    #expect(await serverEvents.next() == .ready)

    net.duplicateNextMessage()
    client.send(Data("a".utf8))
    client.send(Data("b".utf8))
    #expect(await serverEvents.next() == .message(Data("a".utf8)))
    #expect(await serverEvents.next() == .message(Data("a".utf8)))
    #expect(await serverEvents.next() == .message(Data("b".utf8)))
}
