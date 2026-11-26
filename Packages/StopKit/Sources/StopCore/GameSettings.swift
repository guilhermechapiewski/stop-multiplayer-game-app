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

    public init(categories: [String], stopsRequired: Int, allowGiveUp: Bool) {
        self.categories = categories
        self.stopsRequired = stopsRequired
        self.allowGiveUp = allowGiveUp
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
        return GameSettings(categories: cleaned, stopsRequired: stopsRequired, allowGiveUp: allowGiveUp)
    }
}
