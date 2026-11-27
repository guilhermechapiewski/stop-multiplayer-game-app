import Foundation

/// Pure game rules. Every successful change bumps `GameState.version` by exactly 1;
/// a failed intent leaves the state untouched.
public enum GameEngine {
    public static func newGame(gameID: UUID, hostID: PlayerID, hostName: String, settings: GameSettings,
                               language: GameLanguage) throws(GameError) -> GameState {
        let name = hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw .invalidSettings }
        return GameState(gameID: gameID, hostID: hostID, version: 0, language: language,
                         settings: try settings.validated(),
                         players: [Player(id: hostID, name: name, presence: .present)],
                         phase: .lobby, rounds: [], usedLetters: [])
    }

    public static func apply(_ intent: Intent, from sender: PlayerID, to state: inout GameState,
                             using rng: inout some RandomNumberGenerator) throws(GameError) {
        var copy = state
        if try dispatch(intent, from: sender, to: &copy, using: &rng) {
            copy.version += 1
        }
        state = copy
    }

    /// Called by the session when a peer connects or goes quiet. Only toggles between `.present` and `.away`
    /// (never overrides left/removed). Returns true, after bumping `version` once, when it changed.
    public static func setPresence(_ presence: Presence, for player: PlayerID, in state: inout GameState) -> Bool {
        guard let index = state.players.firstIndex(where: { $0.id == player }),
              state.players[index].presence.isActive, presence.isActive,
              state.players[index].presence != presence else { return false }
        state.players[index].presence = presence
        reevaluateRound(&state)
        state.version += 1
        return true
    }

    /// Returns true when the state changed.
    private static func dispatch(_ intent: Intent, from sender: PlayerID, to state: inout GameState,
                                 using rng: inout some RandomNumberGenerator) throws(GameError) -> Bool {
        if case .join(let name) = intent { return try join(name: name, sender: sender, state: &state) }
        guard state.player(sender) != nil else { throw .unknownPlayer }
        switch intent {
        case .join:
            return false
        case .leave:
            return try leave(sender: sender, state: &state)
        case .removePlayer(let id):
            return try removePlayer(id, sender: sender, state: &state)
        case .updateSettings(let settings):
            return try updateSettings(settings, sender: sender, state: &state)
        case .updateRoundSettings(let stopsRequired, let allowGiveUp):
            return try updateRoundSettings(stopsRequired: stopsRequired, allowGiveUp: allowGiveUp,
                                           sender: sender, state: &state)
        case .startGame:
            return try startGame(sender: sender, state: &state, using: &rng)
        case .stop(let answers):
            return try stop(answers, kind: .stop, sender: sender, state: &state)
        case .giveUp(let answers):
            return try stop(answers, kind: .giveUp, sender: sender, state: &state)
        case .forceEndRound:
            return try forceEndRound(sender: sender, state: &state)
        case .submitAnswers(let round, let answers):
            return try submitAnswers(round: round, answers: answers, sender: sender, state: &state)
        case .continueToScoring:
            return try continueToScoring(sender: sender, state: &state)
        case .setScore(let round, let category, let points, let player):
            return try setScore(round: round, category: category, points: points, player: player,
                                sender: sender, state: &state)
        case .nextCategory(let round, let category):
            return try nextCategory(round: round, category: category, sender: sender, state: &state)
        case .nextRound:
            return try nextRound(sender: sender, state: &state, using: &rng)
        case .endGame:
            return try endGame(sender: sender, state: &state)
        }
    }
}
