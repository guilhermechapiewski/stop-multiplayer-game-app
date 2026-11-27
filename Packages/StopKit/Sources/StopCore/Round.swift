public enum StopKind: String, Codable, Sendable { case stop, giveUp }

public struct StopRecord: Codable, Sendable, Equatable {
    public var playerID: PlayerID
    public var kind: StopKind

    public init(playerID: PlayerID, kind: StopKind) {
        self.playerID = playerID
        self.kind = kind
    }
}

public struct Round: Codable, Sendable, Equatable {
    public var number: Int
    public var letter: String
    public var participants: [PlayerID]
    public var stops: [StopRecord]
    public var answers: [PlayerID: [String]]
    public var scores: [PlayerID: [Int?]]
    public var forceEnded: Bool
    /// The furthest scoring has got in this round once the host went back (the category index, or the
    /// category count for the round results); nil until then. Late answers never fill a category up to it.
    /// Optional, so states saved or sent without it still decode.
    public var furthestCategory: Int?

    public init(number: Int, letter: String, participants: [PlayerID], stops: [StopRecord] = [],
                answers: [PlayerID: [String]] = [:], scores: [PlayerID: [Int?]] = [:], forceEnded: Bool = false,
                furthestCategory: Int? = nil) {
        self.number = number
        self.letter = letter
        self.participants = participants
        self.stops = stops
        self.answers = answers
        self.scores = scores
        self.forceEnded = forceEnded
        self.furthestCategory = furthestCategory
    }
}
