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

    /// True from the letter reveal until the round's results.
    public var isRoundInProgress: Bool {
        switch phase {
        case .revealing, .countdown, .writing, .collecting, .scoring: !rounds.isEmpty
        case .lobby, .roundResults, .gameOver: false
        }
    }

    /// `settings.stopsRequired` capped by current-round participants who haven't left or been removed; at least 1.
    public var effectiveStopsRequired: Int {
        let remaining = currentRound?.participants.filter { player($0)?.presence.isActive == true }.count ?? 0
        return max(1, min(settings.stopsRequired, remaining))
    }
}

extension GameState {
    /// The snapshot `viewer` may see: before scoring, the current round keeps the viewer's own answers; everyone
    /// else's entry stays (so screens can show who has sent answers) but is emptied to `[]`, revealing nothing
    /// about what, or how much, they wrote.
    ///
    /// During scoring in read-aloud mode (`settings.silentScoring` off), another player's answer for a category
    /// is withheld, sent as "", while their score for it is nil; once scored (by them, or by the host for an
    /// away or left player) it's included. A nil score always means a non-blank answer (blank ones start at 0),
    /// so a "" with a nil score reads as "hidden", never as "blank". Only the current round can have nil scores.
    /// The viewer's own entry is always intact, and the host also sees the answers of players who are away or
    /// gone, since it may score for them. The results and game over show everything.
    public func redacted(for viewer: PlayerID) -> GameState {
        switch phase {
        case .scoring where !settings.silentScoring:
            guard let round = currentRound else { return self }
            var copy = self
            let index = rounds.count - 1
            let scoresForOthers = viewer == hostID
            for (id, answers) in round.answers where id != viewer {
                if scoresForOthers, player(id)?.presence != .present { continue }
                let scores = round.scores[id] ?? []
                copy.rounds[index].answers[id] = answers.enumerated().map { category, answer in
                    scores.indices.contains(category) && scores[category] != nil ? answer : ""
                }
            }
            return copy
        case .revealing, .countdown, .writing, .collecting:
            guard !rounds.isEmpty else { return self }
            var copy = self
            let index = rounds.count - 1
            copy.rounds[index].answers = Dictionary(uniqueKeysWithValues: rounds[index].answers.map { id, answers in
                (id, id == viewer ? answers : [])
            })
            return copy
        case .lobby, .scoring, .roundResults, .gameOver:
            return self
        }
    }
}
