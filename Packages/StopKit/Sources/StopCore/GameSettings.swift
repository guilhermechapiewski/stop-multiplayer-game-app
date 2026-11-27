import Foundation

public enum GameError: Error, Codable, Sendable, Equatable {
    case notHost, wrongPhase, gameClosed, unknownPlayer, invalidSettings,
         answersIncomplete, giveUpNotAllowed, alreadyStopped, notParticipant,
         invalidScore, cannotScoreForOthers, notEnoughPlayers, staleRound
}

public struct GameSettings: Codable, Sendable, Equatable {
    public var categories: [String]
    public var stopsRequired: Int
    public var allowGiveUp: Bool
    /// Silent mode: everyone's answers show as soon as a scoring category opens. Off (the default) is read-aloud
    /// mode: another player's answer stays hidden until that player's score for it is in, so everyone reads
    /// theirs out loud first (see `GameState.redacted(for:)`).
    public var silentScoring: Bool

    public init(categories: [String], stopsRequired: Int, allowGiveUp: Bool, silentScoring: Bool = false) {
        self.categories = categories
        self.stopsRequired = stopsRequired
        self.allowGiveUp = allowGiveUp
        self.silentScoring = silentScoring
    }

    /// Settings saved or sent before silent mode existed decode as read-aloud mode.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        categories = try container.decode([String].self, forKey: .categories)
        stopsRequired = try container.decode(Int.self, forKey: .stopsRequired)
        allowGiveUp = try container.decode(Bool.self, forKey: .allowGiveUp)
        silentScoring = try container.decodeIfPresent(Bool.self, forKey: .silentScoring) ?? false
    }

    /// Trims categories, drops empty ones, dedupes case-insensitively (first wins).
    public func validated() throws(GameError) -> GameSettings {
        var seen = Set<String>()
        var cleaned: [String] = []
        for raw in categories {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { continue }
            if seen.insert(name.lowercased()).inserted { cleaned.append(name) }
        }
        guard !cleaned.isEmpty, stopsRequired >= 1 else { throw .invalidSettings }
        return GameSettings(categories: cleaned, stopsRequired: stopsRequired, allowGiveUp: allowGiveUp,
                            silentScoring: silentScoring)
    }
}
