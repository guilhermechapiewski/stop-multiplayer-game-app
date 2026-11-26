public struct RankedEntry: Equatable, Sendable {
    public let playerID: PlayerID
    public let rank: Int
    public let points: Int

    public init(playerID: PlayerID, rank: Int, points: Int) {
        self.playerID = playerID
        self.rank = rank
        self.points = points
    }
}

public enum Standings {
    /// Competition ranking (1, 1, 3). Every player in `players` is included (even left or removed);
    /// missing points count as 0; ties keep `players` order.
    public static func rank(_ points: [PlayerID: Int], players: [Player]) -> [RankedEntry] {
        let scored = players.enumerated().map { (index: $0.offset, id: $0.element.id, points: points[$0.element.id] ?? 0) }
        let sorted = scored.sorted { $0.points != $1.points ? $0.points > $1.points : $0.index < $1.index }
        return sorted.map { entry in
            RankedEntry(playerID: entry.id,
                        rank: 1 + sorted.filter { $0.points > entry.points }.count,
                        points: entry.points)
        }
    }

    /// Sum of non-nil scores per player for one round.
    public static func roundPoints(_ round: Round) -> [PlayerID: Int] {
        round.scores.mapValues { $0.compactMap { $0 }.reduce(0, +) }
    }
}
