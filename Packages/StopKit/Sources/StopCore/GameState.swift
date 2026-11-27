import Foundation

public struct GameState: Codable, Sendable, Equatable {
    public var gameID: UUID
    public var hostID: PlayerID
    public var version: Int
    public var language: GameLanguage
    public var settings: GameSettings
    public var players: [Player]
    public var phase: Phase
    public var rounds: [Round]
    public var usedLetters: [String]

    public init(gameID: UUID, hostID: PlayerID, version: Int, language: GameLanguage, settings: GameSettings,
                players: [Player], phase: Phase, rounds: [Round], usedLetters: [String]) {
        self.gameID = gameID
        self.hostID = hostID
        self.version = version
        self.language = language
        self.settings = settings
        self.players = players
        self.phase = phase
        self.rounds = rounds
        self.usedLetters = usedLetters
    }

    /// The last round; nil in the lobby before any round starts.
    public var currentRound: Round? { rounds.last }

    public func player(_ id: PlayerID) -> Player? { players.first { $0.id == id } }

    /// Players who are present or away.
    public var activePlayers: [Player] { players.filter { $0.presence.isActive } }

    /// Sum of non-nil scores over all rounds.
    public var totals: [PlayerID: Int] {
        var result: [PlayerID: Int] = [:]
        for round in rounds {
            for (id, scores) in round.scores { result[id, default: 0] += scores.compactMap { $0 }.reduce(0, +) }
        }
        return result
    }

    /// `settings.stopsRequired` capped by current-round participants who haven't left or been removed; at least 1.
    public var effectiveStopsRequired: Int {
        let remaining = currentRound?.participants.filter { player($0)?.presence.isActive == true }.count ?? 0
        return max(1, min(settings.stopsRequired, remaining))
    }
}

extension GameState {
    /// The snapshot `viewer` may see: before scoring, the current round's answers keep only the viewer's own entry.
    public func redacted(for viewer: PlayerID) -> GameState {
        switch phase {
        case .revealing, .countdown, .writing, .collecting:
            guard !rounds.isEmpty else { return self }
            var copy = self
            copy.rounds[rounds.count - 1].answers = copy.rounds[rounds.count - 1].answers.filter { $0.key == viewer }
            return copy
        case .lobby, .scoring, .roundResults, .gameOver:
            return self
        }
    }
}
