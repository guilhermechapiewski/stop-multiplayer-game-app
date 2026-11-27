import Foundation
import Testing
import StopTestSupport
@testable import StopCore

private func send(_ intent: Intent, _ id: PlayerID, _ state: inout GameState) throws {
    var rng = SeededRNG(seed: 7)
    try GameEngine.apply(intent, from: id, to: &state, using: &rng)
}

private let full = ["Ana", "Uva"]

/// Host plus `players - 1` others; ticked to `.writing`.
private func startedGame(players: Int = 3, stopsRequired: Int = 1, allowGiveUp: Bool = false)
    throws -> (state: GameState, ids: [PlayerID]) {
    let host = UUID()
    var s = try GameEngine.newGame(
        gameID: UUID(), hostID: host, hostName: "P0",
        settings: GameSettings(categories: ["Animal", "Fruta"], stopsRequired: stopsRequired, allowGiveUp: allowGiveUp),
        language: .en)
    var ids = [host]
    for i in 1..<players {
        let id = UUID()
        ids.append(id)
        try send(.join(name: "P\(i)"), id, &s)
    }
    try send(.startGame, host, &s)
    while s.phase != .writing { guard GameEngine.tick(&s) else { Issue.record("tick stalled at \(s.phase)"); break } }
    return (s, ids)
}

@Test func ticksRunRevealThenCountdownThenWriting() throws {
    var (s, _) = try startedGame()
    s.phase = .revealing(ticksRemaining: 2)
    var phases: [Phase] = [s.phase]
    let v0 = s.version
    while GameEngine.tick(&s) { phases.append(s.phase) }
    #expect(phases == [.revealing(ticksRemaining: 2), .revealing(ticksRemaining: 1), .countdown(secondsRemaining: 3),
                       .countdown(secondsRemaining: 2), .countdown(secondsRemaining: 1), .writing])
    #expect(s.version == v0 + 5)
    let v = s.version
    #expect(!GameEngine.tick(&s) && s.version == v)
}

@Test func stopRejectedWhileCountingDown() throws {
    var (s, ids) = try startedGame()
    s.phase = .countdown(secondsRemaining: 2)
    #expect(throws: GameError.wrongPhase) { try send(.stop(answers: full), ids[1], &s) }
}

@Test func stopRequiresAllAnswersFilled() throws {
    var (s, ids) = try startedGame()
    let before = s
    #expect(throws: GameError.answersIncomplete) { try send(.stop(answers: ["Ana", "  ", "Uva"]), ids[1], &s) }
    #expect(throws: GameError.answersIncomplete) { try send(.stop(answers: ["Ana", "  "]), ids[1], &s) }
    #expect(s == before)
}

@Test func stopRecordsFrozenAnswers() throws {
    var (s, ids) = try startedGame(stopsRequired: 2)
    let v = s.version
    try send(.stop(answers: full), ids[1], &s)
    #expect(s.version == v + 1)
    #expect(s.currentRound?.stops == [StopRecord(playerID: ids[1], kind: .stop)])
    #expect(s.currentRound?.answers[ids[1]] == full)
}

@Test func secondStopFromSamePlayerRejected() throws {
    var (s, ids) = try startedGame(stopsRequired: 2, allowGiveUp: true)
    try send(.stop(answers: full), ids[1], &s)
    #expect(throws: GameError.alreadyStopped) { try send(.stop(answers: full), ids[1], &s) }
    #expect(throws: GameError.alreadyStopped) { try send(.giveUp(answers: ["", ""]), ids[1], &s) }
}

@Test func nonParticipantCannotStop() throws {
    var (s, _) = try startedGame()
    let outsider = UUID()
    #expect(throws: GameError.unknownPlayer) { try send(.stop(answers: full), outsider, &s) }
    s.players.append(Player(id: outsider, name: "Late", presence: .present))
    #expect(throws: GameError.notParticipant) { try send(.stop(answers: full), outsider, &s) }
}

@Test func giveUpRequiresSetting() throws {
    var (s, ids) = try startedGame(allowGiveUp: false)
    #expect(throws: GameError.giveUpNotAllowed) { try send(.giveUp(answers: ["", ""]), ids[1], &s) }
}

@Test func giveUpAllowsBlanks() throws {
    var (s, ids) = try startedGame(stopsRequired: 2, allowGiveUp: true)
    try send(.giveUp(answers: ["", " "]), ids[1], &s)
    #expect(s.currentRound?.stops == [StopRecord(playerID: ids[1], kind: .giveUp)])
    #expect(s.currentRound?.answers[ids[1]] == ["", " "])
    #expect(throws: GameError.answersIncomplete) { try send(.giveUp(answers: [""]), ids[2], &s) }
}

@Test func roundLocksWhenRequiredStopsReached() throws {
    var (s, ids) = try startedGame(stopsRequired: 2)
    try send(.stop(answers: full), ids[0], &s)
    #expect(s.phase == .writing)
    try send(.stop(answers: full), ids[1], &s)
    #expect(s.phase == .collecting)
}

@Test func everybodyGivesUpEndsRound() throws {
    var (s, ids) = try startedGame(players: 3, stopsRequired: 3, allowGiveUp: true)
    for id in ids { try send(.giveUp(answers: ["", ""]), id, &s) }
    guard case .scoring(let index, _) = s.phase else { Issue.record("expected scoring, got \(s.phase)"); return }
    #expect(index == 0)
}

@Test func stopAfterLockIsWrongPhaseAndNotCounted() throws {
    var (s, ids) = try startedGame(stopsRequired: 2)
    try send(.stop(answers: full), ids[0], &s)
    try send(.stop(answers: full), ids[1], &s)
    #expect(s.phase == .collecting)
    #expect(throws: GameError.wrongPhase) { try send(.stop(answers: full), ids[2], &s) }
    #expect(s.currentRound?.stops.count == 2)
}

@Test func stopsRequiredClampedToNonLeftParticipants() throws {
    var (s, ids) = try startedGame(players: 3, stopsRequired: 3)
    try send(.leave, ids[2], &s)
    try send(.stop(answers: full), ids[0], &s)
    #expect(s.phase == .writing)
    try send(.stop(answers: full), ids[1], &s)
    // Locked at 2 stops (not 3); the left player doesn't block, so collecting moves on to scoring.
    guard case .scoring = s.phase else { Issue.record("expected scoring, got \(s.phase)"); return }
}

@Test func awayPlayersDoNotLowerStopsRequired() throws {
    var (s, ids) = try startedGame(players: 3, stopsRequired: 3)
    #expect(GameEngine.setPresence(.away, for: ids[2], in: &s))
    try send(.stop(answers: full), ids[0], &s)
    try send(.stop(answers: full), ids[1], &s)
    #expect(s.phase == .writing)
}

@Test func forceEndRoundHostOnly() throws {
    var (s, ids) = try startedGame(stopsRequired: 3)
    #expect(throws: GameError.notHost) { try send(.forceEndRound, ids[1], &s) }
    try send(.forceEndRound, ids[0], &s)
    #expect(s.phase == .collecting)
    #expect(s.currentRound?.forceEnded == true)
    #expect(throws: GameError.wrongPhase) { try send(.forceEndRound, ids[0], &s) }
}

@Test func submitAnswersForWrongRoundIsStale() throws {
    var (s, ids) = try startedGame(stopsRequired: 3)
    try send(.forceEndRound, ids[0], &s)
    #expect(throws: GameError.staleRound) { try send(.submitAnswers(round: 2, answers: full), ids[1], &s) }
}

@Test func submittedAnswersAreIdempotent() throws {
    var (s, ids) = try startedGame(stopsRequired: 2)
    try send(.stop(answers: full), ids[0], &s)
    try send(.stop(answers: full), ids[1], &s)
    let before = s
    try send(.submitAnswers(round: 1, answers: ["X", "Y"]), ids[0], &s)
    #expect(s == before)
    try send(.submitAnswers(round: 1, answers: ["Caju", ""]), ids[2], &s)
    let again = s
    try send(.submitAnswers(round: 1, answers: ["Z", "Z"]), ids[2], &s)
    #expect(s == again)
}

@Test func collectingAdvancesWhenAllPresentSubmitted() throws {
    var (s, ids) = try startedGame(players: 3, stopsRequired: 1)
    try send(.stop(answers: full), ids[0], &s)
    #expect(s.phase == .collecting)
    try send(.submitAnswers(round: 1, answers: full), ids[1], &s)
    #expect(s.phase == .collecting)
    try send(.submitAnswers(round: 1, answers: ["", ""]), ids[2], &s)
    #expect(s.phase == .scoring(categoryIndex: 0, completed: false))
}

@Test func allBlankCategoryCompletesOnEnteringScoring() throws {
    var (s, ids) = try startedGame(players: 3, stopsRequired: 3)
    try send(.forceEndRound, ids[0], &s)
    for id in ids { try send(.submitAnswers(round: 1, answers: ["", ""]), id, &s) }
    #expect(s.phase == .scoring(categoryIndex: 0, completed: true))
}

@Test func submitAnswersErrors() throws {
    var (s, ids) = try startedGame(players: 3, stopsRequired: 1)
    #expect(throws: GameError.wrongPhase) { try send(.submitAnswers(round: 1, answers: full), ids[1], &s) }
    try send(.stop(answers: full), ids[0], &s)
    #expect(s.phase == .collecting)
    let before = s
    #expect(throws: GameError.answersIncomplete) { try send(.submitAnswers(round: 1, answers: ["Asno"]), ids[1], &s) }
    #expect(throws: GameError.answersIncomplete) {
        try send(.submitAnswers(round: 1, answers: ["Asno", "Abacate", "Roma"]), ids[1], &s)
    }
    let outsider = UUID()
    s.players.append(Player(id: outsider, name: "Late", presence: .present))
    #expect(throws: GameError.notParticipant) { try send(.submitAnswers(round: 1, answers: full), outsider, &s) }
    s.players.removeLast()
    #expect(s == before)
}

@Test func awayParticipantDoesNotBlockCollecting() throws {
    var (s, ids) = try startedGame(players: 3, stopsRequired: 1)
    #expect(GameEngine.setPresence(.away, for: ids[2], in: &s))
    try send(.stop(answers: full), ids[0], &s)
    #expect(s.phase == .collecting)
    try send(.submitAnswers(round: 1, answers: full), ids[1], &s)
    guard case .scoring = s.phase else { Issue.record("expected scoring, got \(s.phase)"); return }
}

@Test func continueToScoringTreatsMissingAsBlank() throws {
    var (s, ids) = try startedGame(players: 3, stopsRequired: 1)
    try send(.stop(answers: full), ids[0], &s)
    #expect(throws: GameError.notHost) { try send(.continueToScoring, ids[1], &s) }
    try send(.continueToScoring, ids[0], &s)
    guard case .scoring = s.phase else { Issue.record("expected scoring, got \(s.phase)"); return }
    #expect(s.currentRound?.answers[ids[1]] == ["", ""])
    #expect(s.currentRound?.answers[ids[2]] == ["", ""])
    #expect(s.currentRound?.answers[ids[0]] == full)
}
