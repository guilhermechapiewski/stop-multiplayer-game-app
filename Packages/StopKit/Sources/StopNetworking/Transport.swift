import Foundation

/// What a host publishes about its game; carried in the Bonjour TXT record.
public struct Advertisement: Codable, Sendable, Equatable {
    public var gameID: UUID
    public var hostName: String
    public var playerCount: Int
    public var protocolVersion: Int
    public var joinable: Bool

    public init(gameID: UUID, hostName: String, playerCount: Int, protocolVersion: Int, joinable: Bool) {
        self.gameID = gameID
        self.hostName = hostName
        self.playerCount = playerCount
        self.protocolVersion = protocolVersion
        self.joinable = joinable
    }

    /// TXT record keys: `g` game ID, `h` host name, `n` player count, `v` protocol version, `j` joinable (`1`/`0`).
    public func txtRecord() -> [String: String] {
        [
            "g": gameID.uuidString,
            "h": hostName,
            "n": String(playerCount),
            "v": String(protocolVersion),
            "j": joinable ? "1" : "0",
        ]
    }

    /// Fails if any key is missing or malformed.
    public init?(txtRecord: [String: String]) {
        guard let gameID = txtRecord["g"].flatMap(UUID.init(uuidString:)),
              let hostName = txtRecord["h"],
              let playerCount = txtRecord["n"].flatMap({ Int($0) }),
              let protocolVersion = txtRecord["v"].flatMap({ Int($0) }),
              let joinable = txtRecord["j"].flatMap({ ["1": true, "0": false][$0] })
        else { return nil }
        self.init(
            gameID: gameID, hostName: hostName, playerCount: playerCount,
            protocolVersion: protocolVersion, joinable: joinable)
    }
}

/// An opaque address a `TransportFactory` can connect to.
public struct EndpointRef: Sendable, Hashable, CustomStringConvertible {
    /// Each transport adds its own case (the Network.framework transport adds an `NWEndpoint` case).
    enum Storage: Sendable, Hashable {
        case inMemory(UUID)
    }

    let storage: Storage

    init(_ storage: Storage) {
        self.storage = storage
    }

    public var description: String {
        switch storage {
        case .inMemory(let id): "inmemory:\(id.uuidString)"
        }
    }
}

/// A game found while browsing. `id` is stable for the same advertised service across result updates.
public struct DiscoveredGame: Sendable, Hashable, Identifiable {
    public let id: String
    public let advertisement: Advertisement
    public let endpoint: EndpointRef

    public static func == (lhs: DiscoveredGame, rhs: DiscoveredGame) -> Bool {
        lhs.id == rhs.id && lhs.advertisement == rhs.advertisement && lhs.endpoint == rhs.endpoint
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(endpoint)
    }
}

public enum ConnectionEvent: Sendable, Equatable {
    case ready
    case message(Data)
    case closed
}

/// A bidirectional, ordered, message-oriented link.
///
/// `events` is single-consumer. It emits `.ready` after `start()` succeeds, then messages in send order,
/// then `.closed` exactly once, after which the stream finishes and `send` is a no-op.
/// A connection that cannot be established emits only `.closed`.
public protocol Connection: AnyObject, Sendable {
    var id: UUID { get }
    var events: AsyncStream<ConnectionEvent> { get }
    func start()
    func send(_ data: Data)
    func close()
}

public enum ListenerEvent: Sendable {
    case ready
    case failed
    /// An incoming connection; the receiver must call `start()` on it.
    case connection(any Connection)
}

public protocol Listener: AnyObject, Sendable {
    func start(advertising ad: Advertisement) -> AsyncStream<ListenerEvent>
    func update(_ ad: Advertisement)
    func stop()
}

public enum BrowserEvent: Sendable {
    /// The full current list of visible games (not a delta).
    case results([DiscoveredGame])
    case permissionDenied
    case failed
}

public protocol Browser: AnyObject, Sendable {
    func start() -> AsyncStream<BrowserEvent>
    func stop()
}

public protocol TransportFactory: Sendable {
    func makeListener() -> any Listener
    func makeBrowser() -> any Browser
    func connect(to endpoint: EndpointRef) -> any Connection
}
