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

    public init(number: Int, letter: String, participants: [PlayerID], stops: [StopRecord] = [],
                answers: [PlayerID: [String]] = [:], scores: [PlayerID: [Int?]] = [:], forceEnded: Bool = false) {
        self.number = number
        self.letter = letter
        self.participants = participants
        self.stops = stops
        self.answers = answers
        self.scores = scores
        self.forceEnded = forceEnded
    }
}
