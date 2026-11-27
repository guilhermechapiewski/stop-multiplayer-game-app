import Foundation

extension GameEngine {
    /// Seeds scores (0 for missing or blank answers, nil otherwise) and opens category 0.
    static func enterScoring(_ state: inout GameState) {
        guard let round = state.currentRound else { return }
        let index = state.rounds.count - 1
        let count = state.settings.categories.count
        for id in round.participants {
            let answers = round.answers[id]
            state.rounds[index].scores[id] = (0..<count).map { initialScore(answers?[$0]) }
        }
        state.phase = .scoring(categoryIndex: 0, completed: settleCategory(0, &state))
    }

    static func setScore(round number: Int, category: Int, points: Int, player: PlayerID, sender: PlayerID,
                         state: inout GameState) throws(GameError) -> Bool {
        guard let round = state.currentRound, round.number == number else { throw .staleRound }
        guard state.phase == .scoring(categoryIndex: category, completed: false) else { throw .wrongPhase }
        guard round.participants.contains(player), let target = state.player(player) else { throw .notParticipant }
        if sender != player && !(sender == state.hostID && target.presence != .present) {
            throw .cannotScoreForOthers
        }
        guard [0, 5, 10].contains(points) else { throw .invalidScore }
        if isBlank(round.answers[player]?[category]) && points != 0 { throw .invalidScore }
        let index = state.rounds.count - 1
        if state.rounds[index].scores[player]?[category] == points { return false }
        state.rounds[index].scores[player]?[category] = points
        advanceIfComplete(&state)
        return true
    }

    /// Answers that arrive during scoring fill only the categories not yet scored.
    static func applyLateAnswers(_ answers: [String], for player: PlayerID, state: inout GameState) {
        guard case .scoring(let current, let completed) = state.phase else { return }
        let index = state.rounds.count - 1
        let first = completed ? current + 1 : current
        guard var scores = state.rounds[index].scores[player] else { return }
        for category in first..<max(first, scores.count) { scores[category] = initialScore(answers[category]) }
        state.rounds[index].scores[player] = scores
    }

    static func nextRound(sender: PlayerID, state: inout GameState,
                          using rng: inout some RandomNumberGenerator) throws(GameError) -> Bool {
        guard sender == state.hostID else { throw .notHost }
        guard state.phase == .roundResults else { throw .wrongPhase }
        let pick = LetterPicker.pick(used: state.usedLetters, using: &rng)
        state.usedLetters = pick.used
        state.rounds.append(Round(number: state.rounds.count + 1, letter: pick.letter,
                                  participants: state.activePlayers.map(\.id)))
        state.phase = .revealing(ticksRemaining: 2)
        return true
    }

    static func endGame(sender: PlayerID, state: inout GameState) throws(GameError) -> Bool {
        guard sender == state.hostID else { throw .notHost }
        if state.phase == .gameOver { return false }
        state.phase = .gameOver
        return true
    }

    /// One tick in `.scoring(i, completed: true)`: next category, or round results after the last one.
    static func advanceScoring(_ state: inout GameState) -> Bool {
        guard case .scoring(let current, true) = state.phase else { return false }
        let next = current + 1
        if next < state.settings.categories.count {
            state.phase = .scoring(categoryIndex: next, completed: settleCategory(next, &state))
        } else {
            state.phase = .roundResults
        }
        return true
    }

    /// True when every present or away participant has a score for `category`; then left/removed
    /// participants' missing scores become 0.
    static func settleCategory(_ category: Int, _ state: inout GameState) -> Bool {
        guard let round = state.currentRound else { return false }
        let complete = round.participants.allSatisfy { id in
            state.player(id)?.presence.isActive != true || round.scores[id]?[category] != nil
        }
        guard complete else { return false }
        let index = state.rounds.count - 1
        for id in round.participants where round.scores[id]?[category] == nil {
            state.rounds[index].scores[id]?[category] = 0
        }
        return true
    }

    /// Missing answers count as blank.
    private static func isBlank(_ answer: String?) -> Bool { answer.map(AnswerText.isBlank) ?? true }

    /// Blank answers are fixed at 0; others wait for a pick.
    private static func initialScore(_ answer: String?) -> Int? { isBlank(answer) ? 0 : nil }
}
