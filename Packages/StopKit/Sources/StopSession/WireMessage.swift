import Foundation
import StopCore

/// The wire protocol version. 2 = build 3 (read-aloud redaction in snapshots, previous/next category, re-roll);
/// 1 = builds 1 and 2. Phones only play together on the same version.
public let currentProtocolVersion = 2

public enum RejectReason: String, Codable, Sendable { case versionMismatch, gameClosed, wrongGame }

extension WireMessage.Body {
    /// The wire form: `Body`'s own cases, except that `hello`'s `explicitRejoin` may be missing (a build from
    /// before it existed sends none). It then decodes as false, so the host still reads the hello and answers
    /// with its version check instead of dropping a message it can't decode.
    private enum Wire: Codable {
        case hello(playerID: PlayerID, name: String, gameID: UUID?, lastVersion: Int?, explicitRejoin: Bool?)
        case welcome(GameState)
        case rejected(RejectReason)
        case intent(id: UUID, Intent)
        case ack(id: UUID, error: GameError?)
        case snapshot(GameState)
        case heartbeat, goingAway, bye
    }

    public init(from decoder: any Decoder) throws {
        self = switch try Wire(from: decoder) {
        case let .hello(playerID, name, gameID, lastVersion, explicitRejoin):
            .hello(playerID: playerID, name: name, gameID: gameID, lastVersion: lastVersion,
                   explicitRejoin: explicitRejoin ?? false)
        case .welcome(let state): .welcome(state)
        case .rejected(let reason): .rejected(reason)
        case let .intent(id, intent): .intent(id: id, intent)
        case let .ack(id, error): .ack(id: id, error: error)
        case .snapshot(let state): .snapshot(state)
        case .heartbeat: .heartbeat
        case .goingAway: .goingAway
        case .bye: .bye
        }
    }

    public func encode(to encoder: any Encoder) throws {
        let wire: Wire = switch self {
        case let .hello(playerID, name, gameID, lastVersion, explicitRejoin):
            .hello(playerID: playerID, name: name, gameID: gameID, lastVersion: lastVersion,
                   explicitRejoin: explicitRejoin)
        case .welcome(let state): .welcome(state)
        case .rejected(let reason): .rejected(reason)
        case let .intent(id, intent): .intent(id: id, intent)
        case let .ack(id, error): .ack(id: id, error: error)
        case .snapshot(let state): .snapshot(state)
        case .heartbeat: .heartbeat
        case .goingAway: .goingAway
        case .bye: .bye
        }
        try wire.encode(to: encoder)
    }
}

public struct WireMessage: Codable, Sendable, Equatable {
    public var protocolVersion: Int
    public var body: Body

    public enum Body: Codable, Sendable, Equatable {
        /// `explicitRejoin`: the player chose this game in the Join list (not an automatic reconnect or a
        /// rejoin after relaunch). Only then does the host take back a player it removed.
        case hello(playerID: PlayerID, name: String, gameID: UUID?, lastVersion: Int?, explicitRejoin: Bool)
        case welcome(GameState)
        case rejected(RejectReason)
        case intent(id: UUID, Intent)
        case ack(id: UUID, error: GameError?)
        case snapshot(GameState)
        case heartbeat, goingAway, bye
    }

    public init(protocolVersion: Int = currentProtocolVersion, body: Body) {
        self.protocolVersion = protocolVersion
        self.body = body
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decode(_ data: Data) throws -> WireMessage { try JSONDecoder().decode(WireMessage.self, from: data) }
}
