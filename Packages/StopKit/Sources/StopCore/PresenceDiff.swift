public struct PresenceChange: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case wentAway, returned, left, removed }
    public let playerID: PlayerID
    public let kind: Kind

    public init(playerID: PlayerID, kind: Kind) {
        self.playerID = playerID
        self.kind = kind
    }
}

public enum PresenceDiff {
    /// Presence transitions of players known in both states, in join order.
    /// Empty when `old` is nil or belongs to a different game; newly joined players aren't reported.
    public static func changes(from old: GameState?, to new: GameState) -> [PresenceChange] {
        guard let old, old.gameID == new.gameID else { return [] }
        return new.players.compactMap { player in
            guard let before = old.player(player.id)?.presence, before != player.presence else { return nil }
            let kind: PresenceChange.Kind = switch player.presence {
            case .away: .wentAway
            case .present: .returned
            case .left: .left
            case .removed: .removed
            }
            return PresenceChange(playerID: player.id, kind: kind)
        }
    }
}
