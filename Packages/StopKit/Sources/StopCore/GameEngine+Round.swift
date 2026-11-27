import Foundation

extension GameEngine {
    /// Advances reveal and countdown phases by one second. Returns true (and bumps `version` once) when it changed.
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
        if state.rounds[index].stops.count >= state.effectiveStopsRequired {
            state.phase = .collecting
            advanceIfComplete(&state)
        }
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
        advanceIfComplete(&state)
        return true
    }

    static func continueToScoring(sender: PlayerID, state: inout GameState) throws(GameError) -> Bool {
        guard sender == state.hostID else { throw .notHost }
        guard state.phase == .collecting, let round = state.currentRound else { throw .wrongPhase }
        let blank = Array(repeating: "", count: state.settings.categories.count)
        for id in round.participants where round.answers[id] == nil {
            state.rounds[state.rounds.count - 1].answers[id] = blank
        }
        enterScoring(&state)
        return true
    }

    /// In `.collecting`, moves on once every present participant has answers. Away, left and removed players don't block.
    static func advanceIfComplete(_ state: inout GameState) {
        guard state.phase == .collecting, let round = state.currentRound else { return }
        let waiting = round.participants.contains {
            state.player($0)?.presence == .present && round.answers[$0] == nil
        }
        if !waiting { enterScoring(&state) }
    }

    /// Stub until Task 6 defines scoring.
    static func enterScoring(_ state: inout GameState) {
        state.phase = .scoring(categoryIndex: 0, completed: false)
    }
}
