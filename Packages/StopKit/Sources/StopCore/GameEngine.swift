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

    /// Advances time-based phases. Implemented in a later task.
    public static func tick(_ state: inout GameState) -> Bool { false }

    /// Minimal present/away toggle; Task 6 owns the full behavior.
    public static func setPresence(_ presence: Presence, for player: PlayerID, in state: inout GameState) -> Bool {
        guard let index = state.players.firstIndex(where: { $0.id == player }),
              state.players[index].presence.isActive, presence.isActive,
              state.players[index].presence != presence else { return false }
        state.players[index].presence = presence
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
        case .nextRound, .endGame, .forceEndRound, .continueToScoring, .stop, .giveUp, .submitAnswers, .setScore:
            throw .wrongPhase
        }
    }
}
