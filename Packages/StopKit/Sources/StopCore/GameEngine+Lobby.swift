import Foundation

extension GameEngine {
    static func join(name: String, sender: PlayerID, state: inout GameState) throws(GameError) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .invalidSettings }
        if let index = state.players.firstIndex(where: { $0.id == sender }) {
            let player = state.players[index]
            if player.presence == .present && player.name == trimmed { return false }
            state.players[index].presence = .present
            state.players[index].name = trimmed
            return true
        }
        guard state.phase == .lobby else { throw .gameClosed }
        state.players.append(Player(id: sender, name: trimmed, presence: .present))
        return true
    }

    static func leave(sender: PlayerID, state: inout GameState) throws(GameError) -> Bool {
        guard sender != state.hostID else { throw .notHost }
        guard let index = state.players.firstIndex(where: { $0.id == sender }) else { throw .unknownPlayer }
        guard state.players[index].presence.isActive else { return false }
        state.players[index].presence = .left
        reevaluateRound(&state)
        return true
    }

    static func removePlayer(_ id: PlayerID, sender: PlayerID, state: inout GameState) throws(GameError) -> Bool {
        guard sender == state.hostID else { throw .notHost }
        guard id != state.hostID else { throw .notHost }
        guard let index = state.players.firstIndex(where: { $0.id == id }) else { throw .unknownPlayer }
        if state.players[index].presence == .removed { return false }
        state.players[index].presence = .removed
        reevaluateRound(&state)
        return true
    }

    static func updateSettings(_ settings: GameSettings, sender: PlayerID, state: inout GameState) throws(GameError) -> Bool {
        guard sender == state.hostID else { throw .notHost }
        guard state.phase == .lobby else { throw .wrongPhase }
        let validated = try settings.validated()
        guard validated != state.settings else { return false }
        state.settings = validated
        return true
    }

    static func updateRoundSettings(stopsRequired: Int, allowGiveUp: Bool, sender: PlayerID,
                                    state: inout GameState) throws(GameError) -> Bool {
        guard sender == state.hostID else { throw .notHost }
        guard state.phase == .lobby || state.phase == .roundResults else { throw .wrongPhase }
        guard stopsRequired >= 1 else { throw .invalidSettings }
        if state.settings.stopsRequired == stopsRequired && state.settings.allowGiveUp == allowGiveUp { return false }
        state.settings.stopsRequired = stopsRequired
        state.settings.allowGiveUp = allowGiveUp
        return true
    }

    static func startGame(sender: PlayerID, state: inout GameState,
                          using rng: inout some RandomNumberGenerator) throws(GameError) -> Bool {
        guard sender == state.hostID else { throw .notHost }
        guard state.phase == .lobby else { throw .wrongPhase }
        let present = state.players.filter { $0.presence == .present }.map(\.id)
        guard present.count >= 2 else { throw .notEnoughPlayers }
        let pick = LetterPicker.pick(used: state.usedLetters, using: &rng)
        state.usedLetters = pick.used
        state.rounds.append(Round(number: 1, letter: pick.letter, participants: present))
        state.phase = .revealing(ticksRemaining: 2)
        return true
    }
}
