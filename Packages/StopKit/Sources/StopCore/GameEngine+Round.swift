import Foundation

extension GameEngine {
    /// Advances the reveal and countdown by one tick (scoring moves on only when the host says so). Returns true
    /// (and bumps `version` once) when it changed.
    public static func tick(_ state: inout GameState) -> Bool {
        let next: Phase
        switch state.phase {
        case .revealing(let ticks):
            next = ticks > 1 ? .revealing(ticksRemaining: ticks - 1) : .countdown(secondsRemaining: 3)
        case .countdown(let seconds):
            next = seconds > 1 ? .countdown(secondsRemaining: seconds - 1) : .writing
        default:
            return false
        }
        state.phase = next
        state.version += 1
        return true
    }

    /// The host swaps the round's letter during the reveal or the countdown, as often as it likes: a new letter
    /// that's neither `letter` nor used yet this game (`letter` goes back to the pool), and the reveal starts
    /// over so everyone sees it land and gets the full countdown. `letter` is the one the host is replacing: a
    /// stale or repeated request (the letter already changed) is rejected, so one tap never rolls twice.
    static func rerollLetter(round number: Int, letter: String, sender: PlayerID, state: inout GameState,
                             using rng: inout some RandomNumberGenerator) throws(GameError) -> Bool {
        guard sender == state.hostID else { throw .notHost }
        guard let round = state.currentRound else { throw .wrongPhase }
        guard round.number == number, round.letter == letter else { throw .staleRound }
        switch state.phase {
        case .revealing, .countdown: break
        default: throw .wrongPhase
        }
        let pick = LetterPicker.reroll(current: letter, used: state.usedLetters, using: &rng)
        state.usedLetters = pick.used
        state.rounds[state.rounds.count - 1].letter = pick.letter
        state.phase = .revealing(ticksRemaining: 2)
        return true
    }

    static func stop(_ answers: [String], kind: StopKind, sender: PlayerID,
                     state: inout GameState) throws(GameError) -> Bool {
        guard state.phase == .writing, let round = state.currentRound else { throw .wrongPhase }
        guard round.participants.contains(sender) else { throw .notParticipant }
        if kind == .giveUp && !state.settings.allowGiveUp { throw .giveUpNotAllowed }
        guard !round.stops.contains(where: { $0.playerID == sender }) else { throw .alreadyStopped }
        guard answers.count == state.settings.categories.count else { throw .answersIncomplete }
        if kind == .stop && answers.contains(where: AnswerText.isBlank) { throw .answersIncomplete }
        let index = state.rounds.count - 1
        state.rounds[index].stops.append(StopRecord(playerID: sender, kind: kind))
        state.rounds[index].answers[sender] = answers
        reevaluateRound(&state)
        return true
    }

    static func forceEndRound(sender: PlayerID, state: inout GameState) throws(GameError) -> Bool {
        guard sender == state.hostID else { throw .notHost }
        guard state.phase == .writing, !state.rounds.isEmpty else { throw .wrongPhase }
        state.rounds[state.rounds.count - 1].forceEnded = true
        state.phase = .collecting
        advanceIfComplete(&state)
        return true
    }

    static func submitAnswers(round number: Int, answers: [String], sender: PlayerID,
                              state: inout GameState) throws(GameError) -> Bool {
        guard let round = state.currentRound, round.number == number else { throw .staleRound }
        switch state.phase {
        case .collecting, .scoring: break
        default: throw .wrongPhase
        }
        guard round.participants.contains(sender) else { throw .notParticipant }
        if round.answers[sender] != nil { return false }
        guard answers.count == state.settings.categories.count else { throw .answersIncomplete }
        state.rounds[state.rounds.count - 1].answers[sender] = answers
        applyLateAnswers(answers, for: sender, state: &state)
        advanceIfComplete(&state)
        return true
    }

    static func continueToScoring(sender: PlayerID, state: inout GameState) throws(GameError) -> Bool {
        guard sender == state.hostID else { throw .notHost }
        guard state.phase == .collecting, state.currentRound != nil else { throw .wrongPhase }
        // Missing answers stay missing: they score 0 for now, and if they arrive later (the player reconnects)
        // they fill the categories not yet scored.
        enterScoring(&state)
        return true
    }

    /// Re-checks the round after stops or participant/presence changes: in `.writing`, locks once enough
    /// players stopped; then lets collecting or scoring move on if nobody blocks it any more.
    static func reevaluateRound(_ state: inout GameState) {
        if state.phase == .writing, let round = state.currentRound, round.stops.count >= state.effectiveStopsRequired {
            state.phase = .collecting
        }
        advanceIfComplete(&state)
    }

    /// In `.collecting`, moves on once every present participant has answers (away, left and removed players
    /// don't block). In the current scoring category, recomputes whether every active participant has a score.
    static func advanceIfComplete(_ state: inout GameState) {
        switch state.phase {
        case .collecting:
            guard let round = state.currentRound else { return }
            let waiting = round.participants.contains {
                state.player($0)?.presence == .present && round.answers[$0] == nil
            }
            if !waiting { enterScoring(&state) }
        case .scoring(let category, _):
            state.phase = .scoring(categoryIndex: category, completed: settleCategory(category, &state))
        default:
            return
        }
    }
}
