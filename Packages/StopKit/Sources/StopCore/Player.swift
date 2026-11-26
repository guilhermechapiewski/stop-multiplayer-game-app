public enum Presence: String, Codable, Sendable { case present, away, left, removed }

public struct Player: Codable, Sendable, Equatable {
    public var id: PlayerID
    public var name: String
    public var presence: Presence

    public init(id: PlayerID, name: String, presence: Presence) {
        self.id = id
        self.name = name
        self.presence = presence
    }
}
