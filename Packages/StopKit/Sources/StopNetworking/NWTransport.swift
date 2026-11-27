import Foundation
import Network
import Synchronization

/// The real transport: Bonjour discovery, TCP over Wi-Fi and peer-to-peer Wi-Fi, length-prefixed frames.
public final class NWTransportFactory: TransportFactory {
    private let serviceType: String
    /// False only in tests: the listener then accepts on a port without registering a Bonjour service.
    private let advertises: Bool

    public convenience init(serviceType: String = "_stopgame._tcp") {
        self.init(serviceType: serviceType, advertises: true)
    }

    init(serviceType: String, advertises: Bool) {
        self.serviceType = serviceType
        self.advertises = advertises
    }

    public func makeListener() -> any Listener {
        NWTransportListener(serviceType: serviceType, advertises: advertises)
    }

    public func makeBrowser() -> any Browser {
        NWTransportBrowser(serviceType: serviceType)
    }

    public func connect(to endpoint: EndpointRef) -> any Connection {
        guard case .network(let nwEndpoint) = endpoint.storage else {
            preconditionFailure("NWTransportFactory cannot connect to \(endpoint)")
        }
        return NWConnectionAdapter(NWConnection(to: nwEndpoint, using: NWConnectionAdapter.parameters()))
    }

    /// Direct connection to an address, bypassing discovery (tests).
    func connect(host: NWEndpoint.Host, port: NWEndpoint.Port) -> any Connection {
        connect(to: EndpointRef(.network(.hostPort(host: host, port: port))))
    }
}

// MARK: - Listener

final class NWTransportListener: Listener {
    private let serviceType: String
    private let advertises: Bool
    private let queue = DispatchQueue(label: "stop.net.listener")
    private let state = Mutex<Running?>(nil)

    private struct Running {
        let listener: NWListener
        let events: AsyncStream<ListenerEvent>.Continuation
    }

    init(serviceType: String, advertises: Bool) {
        self.serviceType = serviceType
        self.advertises = advertises
    }

    deinit {
        stop()
    }

    /// The bound port once the listener is ready (tests).
    var port: NWEndpoint.Port? {
        state.withLock { $0?.listener.port }
    }

    func start(advertising ad: Advertisement) -> AsyncStream<ListenerEvent> {
        stop()
        let (stream, continuation) = AsyncStream.makeStream(of: ListenerEvent.self)
        let listener: NWListener
        do {
            listener = try NWListener(using: NWConnectionAdapter.parameters())
        } catch {
            continuation.yield(.failed)
            continuation.finish()
            return stream
        }
        if advertises { listener.service = service(ad) }
        // The handlers capture only the continuation (and the listener weakly), so there is no retain cycle.
        // `stop()` finishes the continuation before cancelling, so a requested stop emits no `.failed`.
        listener.stateUpdateHandler = { [weak listener] newState in
            switch newState {
            case .ready:
                continuation.yield(.ready)
            case .failed, .cancelled:
                continuation.yield(.failed)
                continuation.finish()
                listener?.cancel()
            case .setup, .waiting:
                break
            @unknown default:
                break
            }
        }
        listener.newConnectionHandler = { connection in
            // Not started: the receiver calls `start()`. If nobody takes it, the adapter's deinit cancels it.
            continuation.yield(.connection(NWConnectionAdapter(connection)))
        }
        state.withLock { $0 = Running(listener: listener, events: continuation) }
        listener.start(queue: queue)
        return stream
    }

    func update(_ ad: Advertisement) {
        guard advertises else { return }
        state.withLock { $0?.listener.service = service(ad) }
    }

    /// Stops advertising and accepting; already-accepted connections stay open.
    func stop() {
        let running = state.withLock { state in
            defer { state = nil }
            return state
        }
        running?.events.finish()
        running?.listener.cancel()
    }

    private func service(_ ad: Advertisement) -> NWListener.Service {
        NWListener.Service(type: serviceType, txtRecord: NWTXTRecord(ad.txtRecord()))
    }
}

// MARK: - Browser

final class NWTransportBrowser: Browser {
    private let serviceType: String
    private let queue = DispatchQueue(label: "stop.net.browser")
    private let state = Mutex<Running?>(nil)

    private struct Running {
        let browser: NWBrowser
        let events: AsyncStream<BrowserEvent>.Continuation
    }

    init(serviceType: String) {
        self.serviceType = serviceType
    }

    deinit {
        stop()
    }

    func start() -> AsyncStream<BrowserEvent> {
        stop()
        let (stream, continuation) = AsyncStream.makeStream(of: BrowserEvent.self)
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: serviceType, domain: nil), using: NWConnectionAdapter.parameters())
        browser.browseResultsChangedHandler = { results, _ in
            continuation.yield(.results(Self.games(from: results)))
        }
        browser.stateUpdateHandler = { [weak browser] newState in
            switch newState {
            case .ready:
                if let browser { continuation.yield(.results(Self.games(from: browser.browseResults))) }
            case .waiting(let error):
                // Waiting for local network permission (or for a network): only the former is actionable.
                if Self.isPolicyDenied(error) { continuation.yield(.permissionDenied) }
            case .failed(let error):
                continuation.yield(Self.isPolicyDenied(error) ? .permissionDenied : .failed)
                continuation.finish()
                browser?.cancel()
            case .setup, .cancelled:
                break
            @unknown default:
                break
            }
        }
        state.withLock { $0 = Running(browser: browser, events: continuation) }
        browser.start(queue: queue)
        return stream
    }

    func stop() {
        let running = state.withLock { state in
            defer { state = nil }
            return state
        }
        running?.events.finish()
        running?.browser.cancel()
    }

    static func isPolicyDenied(_ error: NWError) -> Bool {
        if case .dns(let code) = error { return code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) }
        return false
    }

    /// One game per advertised service, sorted by id. The same service seen on several interfaces (Wi-Fi and
    /// peer-to-peer) collapses into one entry whose endpoint has no interface, so the endpoint is stable across
    /// updates and connecting may use whichever path works. Services with an invalid TXT record are dropped.
    static func games(from results: Set<NWBrowser.Result>) -> [DiscoveredGame] {
        var games: [String: DiscoveredGame] = [:]
        for result in results {
            guard case .service(let name, let type, let domain, _) = result.endpoint,
                  case .bonjour(let txt) = result.metadata,
                  let ad = Advertisement(txtRecord: txt.dictionary)
            else { continue }
            let endpoint = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)
            let id = "\(name).\(type).\(domain)"
            games[id] = DiscoveredGame(id: id, advertisement: ad, endpoint: EndpointRef(.network(endpoint)))
        }
        return games.values.sorted { $0.id < $1.id }
    }
}
