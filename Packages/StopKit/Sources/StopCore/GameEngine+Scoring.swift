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
        guard let round = state.currentRound else { throw .wrongPhase }
        guard round.number == number else { throw .staleRound }
        // A completed category stays editable until the host moves on, so a wrong pick can be corrected.
        guard case .scoring(category, _) = state.phase else { throw .wrongPhase }
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

    /// Answers that arrive during scoring fill only the categories not yet scored: none the host has already
    /// completed, even after going back to an earlier one. The furthest category reached still counts as
    /// unscored when the host left it unfinished, so the late answer can be scored there.
    static func applyLateAnswers(_ answers: [String], for player: PlayerID, state: inout GameState) {
        guard case .scoring(let current, _) = state.phase, let round = state.currentRound else { return }
        let index = state.rounds.count - 1
        // Every category before the furthest one was completed to move past it.
        let furthest = max(round.furthestCategory ?? current, current)
        let first = isComplete(furthest, round, state) ? furthest + 1 : furthest
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

    /// The host moves past a completed category: to the next one (settled as on entering scoring), or to the
    /// round results after the last. A stale or repeated request (another round or category) is rejected, so a
    /// retry never skips a category.
    static func nextCategory(round number: Int, category: Int, sender: PlayerID,
                             state: inout GameState) throws(GameError) -> Bool {
        guard sender == state.hostID else { throw .notHost }
        guard let round = state.currentRound else { throw .wrongPhase }
        guard round.number == number else { throw .staleRound }
        guard state.phase == .scoring(categoryIndex: category, completed: true) else { throw .wrongPhase }
        let next = category + 1
        if next < state.settings.categories.count {
            state.phase = .scoring(categoryIndex: next, completed: settleCategory(next, &state))
        } else {
            state.phase = .roundResults
        }
        return true
    }

    /// The host goes back one category to review or correct its scores: from category `category` (> 0) to the
    /// one before, or from the round results (`category` == the category count) to the last one. Scores there
    /// stay editable as usual. The category index guards it like `nextCategory`: a stale or repeated request
    /// never moves twice. Once the next round has started, earlier rounds are final.
    static func previousCategory(round number: Int, category: Int, sender: PlayerID,
                                 state: inout GameState) throws(GameError) -> Bool {
        guard sender == state.hostID else { throw .notHost }
        guard let round = state.currentRound else { throw .wrongPhase }
        guard round.number == number else { throw .staleRound }
        switch state.phase {
        case .scoring(category, _) where category > 0:
            break
        case .roundResults where category == state.settings.categories.count:
            break
        default:
            throw .wrongPhase
        }
        let index = state.rounds.count - 1
        state.rounds[index].furthestCategory = max(round.furthestCategory ?? category, category)
        let previous = category - 1
        state.phase = .scoring(categoryIndex: previous, completed: settleCategory(previous, &state))
        return true
    }

    /// True when every present or away participant has a score for `category`; then left/removed
    /// participants' missing scores become 0.
    static func settleCategory(_ category: Int, _ state: inout GameState) -> Bool {
        guard let round = state.currentRound, isComplete(category, round, state) else { return false }
        let index = state.rounds.count - 1
        for id in round.participants where round.scores[id]?[category] == nil {
            state.rounds[index].scores[id]?[category] = 0
        }
        return true
    }

    /// True when every present or away participant has a score for `category`.
    private static func isComplete(_ category: Int, _ round: Round, _ state: GameState) -> Bool {
        round.participants.allSatisfy { id in
            state.player(id)?.presence.isActive != true || round.scores[id]?[category] != nil
        }
    }

    /// Missing answers count as blank.
    private static func isBlank(_ answer: String?) -> Bool { answer.map(AnswerText.isBlank) ?? true }

    /// Blank answers are fixed at 0; others wait for a pick.
    private static func initialScore(_ answer: String?) -> Int? { isBlank(answer) ? 0 : nil }
}
