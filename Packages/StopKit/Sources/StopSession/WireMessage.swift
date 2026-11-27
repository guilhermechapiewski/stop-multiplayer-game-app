import Foundation
import StopCore

public let currentProtocolVersion = 1

public enum RejectReason: String, Codable, Sendable { case versionMismatch, gameClosed, wrongGame }

public struct WireMessage: Codable, Sendable, Equatable {
    public var protocolVersion: Int
    public var body: Body

    public enum Body: Codable, Sendable, Equatable {
        case hello(playerID: PlayerID, name: String, gameID: UUID?, lastVersion: Int?)
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
