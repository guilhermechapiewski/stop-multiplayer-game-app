import Foundation
import Synchronization

/// An in-process `TransportFactory` for tests and simulations, with fault injection.
///
/// Delivery is asynchronous and ordered per connection end: every end has a serial inbox drained by its
/// own task, which waits until each message's delivery time (send time + latency, real time) before
/// emitting it. Both ends of a link share the same connection `id`.
///
/// A connection's sends are dropped until `start()` has been called on it; the incoming end accepts
/// messages as soon as the dialing end has started, buffering them until the listener side starts it.
public final class InMemoryNetwork: TransportFactory, Sendable {
    private let state = Mutex(State())

    public init() {}

    // MARK: TransportFactory

    public func makeListener() -> any Listener {
        InMemoryListener(network: self, endpointID: UUID())
    }

    public func makeBrowser() -> any Browser {
        InMemoryBrowser(network: self, id: UUID())
    }

    public func connect(to endpoint: EndpointRef) -> any Connection {
        guard case .inMemory(let listenerID) = endpoint.storage else {
            preconditionFailure("InMemoryNetwork cannot connect to \(endpoint)")
        }
        let linkID = UUID()
        let (events, end) = End.make()
        state.withLock { $0.links[linkID] = Link(listenerID: listenerID, client: end) }
        return InMemoryConnection(network: self, id: linkID, side: .client, events: events)
    }

    // MARK: Fault injection

    /// Delivery delay for all messages sent from now on.
    public func setLatency(_ d: Duration) {
        state.withLock { $0.latency = d }
    }

    /// Abruptly closes every connection (or every connection to `endpoint`'s listener): both ends get `.closed`
    /// and in-flight messages are discarded.
    public func dropAllConnections(of endpoint: EndpointRef? = nil) {
        state.withLock { state in
            for (linkID, link) in state.links where endpoint == nil || endpoint == .inMemory(link.listenerID) {
                state.abort(linkID)
            }
        }
    }

    /// Abruptly closes one connection, both sides.
    public func severClient(_ connectionID: UUID) {
        state.withLock { $0.abort(connectionID) }
    }

    /// An unreachable listener is hidden from browsers and new connections to it fail with `.closed`.
    /// Existing connections are unaffected.
    public func setReachable(_ reachable: Bool, listener: EndpointRef) {
        guard case .inMemory(let listenerID) = listener.storage else { return }
        state.withLock { state in
            if reachable {
                state.unreachable.remove(listenerID)
            } else {
                state.unreachable.insert(listenerID)
            }
            state.publishResults()
        }
    }

    /// The next message sent on any connection is delivered twice.
    public func duplicateNextMessage() {
        state.withLock { $0.duplicateNext = true }
    }

    // MARK: Connection operations

    fileprivate func start(_ linkID: UUID, _ side: Side) {
        let inbox: AsyncStream<Delivery>? = state.withLock { state in
            guard var link = state.links[linkID], var end = link[side], !end.started, !end.closed else { return nil }
            if side == .client {
                guard let listener = state.listeners[link.listenerID], state.isVisible(link.listenerID) else {
                    state.abort(linkID)
                    return nil
                }
                let (serverEvents, serverEnd) = End.make()
                link.server = serverEnd
                listener.events.yield(.connection(
                    InMemoryConnection(network: self, id: linkID, side: .server, events: serverEvents)))
            }
            end.started = true
            end.events.yield(.ready)
            let inbox = end.inboxStream
            end.inboxStream = nil
            link[side] = end
            state.links[linkID] = link
            return inbox
        }
        guard let inbox else { return }
        Task { [self] in
            for await delivery in inbox {
                if delivery.deadline > .now {
                    try? await Task.sleep(until: delivery.deadline, clock: .continuous)
                }
                deliver(delivery.event, linkID, side)
            }
        }
    }

    fileprivate func send(_ data: Data, _ linkID: UUID, from side: Side) {
        state.withLock { state in
            guard let link = state.links[linkID], link.isOpen,
                  link[side]?.started == true, let peer = link[side.peer] else { return }
            let delivery = Delivery(event: .message(data), deadline: .now + state.latency)
            peer.inbox.yield(delivery)
            if state.duplicateNext {
                state.duplicateNext = false
                peer.inbox.yield(delivery)
            }
        }
    }

    /// Graceful close: this end gets `.closed` now; the peer gets it after messages already in flight.
    fileprivate func close(_ linkID: UUID, _ side: Side) {
        state.withLock { state in
            guard var link = state.links[linkID] else { return }
            link.isOpen = false
            link[side]?.finish()
            if let peer = link[side.peer], !peer.closed {
                if peer.started {
                    peer.inbox.yield(Delivery(event: .closed, deadline: .now + state.latency))
                } else {
                    link[side.peer]?.finish()
                }
            }
            state.links[linkID] = link
            state.removeIfFinished(linkID)
        }
    }

    private func deliver(_ event: ConnectionEvent, _ linkID: UUID, _ side: Side) {
        state.withLock { state in
            guard var link = state.links[linkID], var end = link[side], !end.closed else { return }
            if event == .closed {
                end.finish()
            } else {
                end.events.yield(event)
            }
            link[side] = end
            state.links[linkID] = link
            state.removeIfFinished(linkID)
        }
    }

    // MARK: Listener and browser operations

    fileprivate func startListener(_ endpointID: UUID, advertising ad: Advertisement) -> AsyncStream<ListenerEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: ListenerEvent.self)
        continuation.yield(.ready)
        state.withLock { state in
            state.listeners[endpointID]?.events.finish()
            state.nextListenerOrder += 1
            state.listeners[endpointID] = ListenerState(
                ad: ad, order: state.nextListenerOrder, events: continuation)
            state.publishResults()
        }
        return stream
    }

    fileprivate func updateListener(_ endpointID: UUID, _ ad: Advertisement) {
        state.withLock { state in
            guard state.listeners[endpointID] != nil else { return }
            state.listeners[endpointID]?.ad = ad
            state.publishResults()
        }
    }

    /// Stops advertising and accepting; already-accepted connections stay open.
    fileprivate func stopListener(_ endpointID: UUID) {
        state.withLock { state in
            state.listeners.removeValue(forKey: endpointID)?.events.finish()
            state.publishResults()
        }
    }

    fileprivate func startBrowser(_ id: UUID) -> AsyncStream<BrowserEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: BrowserEvent.self)
        state.withLock { state in
            state.browsers.removeValue(forKey: id)?.finish()
            state.browsers[id] = continuation
            continuation.yield(.results(state.visibleGames()))
        }
        return stream
    }

    fileprivate func stopBrowser(_ id: UUID) {
        state.withLock { $0.browsers.removeValue(forKey: id)?.finish() }
    }
}

// MARK: - State

extension EndpointRef {
    fileprivate static func inMemory(_ id: UUID) -> EndpointRef { EndpointRef(.inMemory(id)) }
}

fileprivate enum Side: Sendable {
    case client, server
    var peer: Side { self == .client ? .server : .client }
}

fileprivate struct Delivery: Sendable {
    var event: ConnectionEvent
    var deadline: ContinuousClock.Instant
}

/// One end of a link.
fileprivate struct End {
    let events: AsyncStream<ConnectionEvent>.Continuation
    let inbox: AsyncStream<Delivery>.Continuation
    /// Handed to the delivery task on `start()`.
    var inboxStream: AsyncStream<Delivery>?
    var started = false
    /// `.closed` has been emitted.
    var closed = false

    static func make() -> (AsyncStream<ConnectionEvent>, End) {
        let (events, eventsContinuation) = AsyncStream.makeStream(of: ConnectionEvent.self)
        let (inbox, inboxContinuation) = AsyncStream.makeStream(of: Delivery.self)
        return (events, End(events: eventsContinuation, inbox: inboxContinuation, inboxStream: inbox))
    }

    /// Emits `.closed` once, finishes the stream and stops the delivery task.
    mutating func finish() {
        guard !closed else { return }
        closed = true
        events.yield(.closed)
        events.finish()
        inbox.finish()
    }
}

fileprivate struct Link {
    let listenerID: UUID
    var client: End
    /// Created when the client starts and the listener accepts.
    var server: End?
    /// False once either side closed: no more sends.
    var isOpen = true

    subscript(side: Side) -> End? {
        get { side == .client ? client : server }
        set {
            guard let newValue else { return }
            if side == .client { client = newValue } else { server = newValue }
        }
    }
}

fileprivate struct ListenerState {
    var ad: Advertisement
    /// Start order, so browse results are deterministic.
    let order: Int
    let events: AsyncStream<ListenerEvent>.Continuation
}

fileprivate struct State {
    var latency: Duration = .zero
    var duplicateNext = false
    var links: [UUID: Link] = [:]
    var listeners: [UUID: ListenerState] = [:]
    var nextListenerOrder = 0
    var unreachable: Set<UUID> = []
    var browsers: [UUID: AsyncStream<BrowserEvent>.Continuation] = [:]

    func isVisible(_ listenerID: UUID) -> Bool {
        listeners[listenerID] != nil && !unreachable.contains(listenerID)
    }

    func visibleGames() -> [DiscoveredGame] {
        listeners
            .filter { isVisible($0.key) }
            .sorted { $0.value.order < $1.value.order }
            .map { id, listener in
                let endpoint = EndpointRef.inMemory(id)
                return DiscoveredGame(id: endpoint.description, advertisement: listener.ad, endpoint: endpoint)
            }
    }

    func publishResults() {
        let games = visibleGames()
        for browser in browsers.values { browser.yield(.results(games)) }
    }

    /// Both ends get `.closed` immediately; in-flight messages are dropped.
    mutating func abort(_ linkID: UUID) {
        guard var link = links[linkID] else { return }
        link.isOpen = false
        link.client.finish()
        link.server?.finish()
        links[linkID] = link
        removeIfFinished(linkID)
    }

    mutating func removeIfFinished(_ linkID: UUID) {
        guard let link = links[linkID], link.client.closed, link.server?.closed ?? true else { return }
        links[linkID] = nil
    }
}

// MARK: - Connection, listener, browser

fileprivate final class InMemoryConnection: Connection {
    let id: UUID
    let events: AsyncStream<ConnectionEvent>
    private let network: InMemoryNetwork
    private let side: Side

    init(network: InMemoryNetwork, id: UUID, side: Side, events: AsyncStream<ConnectionEvent>) {
        self.network = network
        self.id = id
        self.side = side
        self.events = events
    }

    func start() { network.start(id, side) }
    func send(_ data: Data) { network.send(data, id, from: side) }
    func close() { network.close(id, side) }
}

fileprivate final class InMemoryListener: Listener {
    private let network: InMemoryNetwork
    private let endpointID: UUID

    init(network: InMemoryNetwork, endpointID: UUID) {
        self.network = network
        self.endpointID = endpointID
    }

    func start(advertising ad: Advertisement) -> AsyncStream<ListenerEvent> {
        network.startListener(endpointID, advertising: ad)
    }

    func update(_ ad: Advertisement) { network.updateListener(endpointID, ad) }
    func stop() { network.stopListener(endpointID) }
}

fileprivate final class InMemoryBrowser: Browser {
    private let network: InMemoryNetwork
    private let id: UUID

    init(network: InMemoryNetwork, id: UUID) {
        self.network = network
        self.id = id
    }

    func start() -> AsyncStream<BrowserEvent> { network.startBrowser(id) }
    func stop() { network.stopBrowser(id) }
}
