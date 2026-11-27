import Foundation
import Testing
import StopTestSupport
@testable import StopCore

private func send(_ intent: Intent, _ id: PlayerID, _ state: inout GameState, seed: UInt64 = 7) throws {
    var rng = SeededRNG(seed: seed)
    try GameEngine.apply(intent, from: id, to: &state, using: &rng)
}

private func score(_ s: inout GameState, _ sender: PlayerID, category: Int, points: Int,
                   for player: PlayerID? = nil) throws {
    let round = s.currentRound?.number ?? 0
    try send(.setScore(round: round, category: category, points: points, player: player ?? sender), sender, &s)
}

/// Host plus `players - 1` others; ticked to `.writing`.
private func writingGame(players: Int = 3, categories: [String] = ["Animal", "Fruta"], stopsRequired: Int = 1)
    throws -> (state: GameState, ids: [PlayerID]) {
    let host = UUID()
    var s = try GameEngine.newGame(
        gameID: UUID(), hostID: host, hostName: "P0",
        settings: GameSettings(categories: categories, stopsRequired: stopsRequired, allowGiveUp: true),
        language: .en)
    var ids = [host]
    for i in 1..<players {
        let id = UUID()
        ids.append(id)
        try send(.join(name: "P\(i)"), id, &s)
    }
    try send(.startGame, host, &s)
    tickToWriting(&s)
    return (s, ids)
}

private func tickToWriting(_ s: inout GameState) {
    while s.phase != .writing { guard GameEngine.tick(&s) else { Issue.record("tick stalled at \(s.phase)"); return } }
}

/// Host force-ends the round, then each player with answers submits them (nil = doesn't submit).
private func collect(_ s: inout GameState, _ ids: [PlayerID], _ answers: [[String]?]) throws {
    try send(.forceEndRound, ids[0], &s)
    for (id, a) in zip(ids, answers) {
        if let a { try send(.submitAnswers(round: s.currentRound!.number, answers: a), id, &s) }
    }
}

/// Everyone submits blanks, so every category completes at once; ticks through to `.roundResults`.
private func playBlankRound(_ s: inout GameState, _ ids: [PlayerID]) throws {
    let blank = Array(repeating: "", count: s.settings.categories.count)
    try collect(&s, ids, ids.map { _ in blank })
    while s.phase != .roundResults { guard GameEngine.tick(&s) else { Issue.record("stalled at \(s.phase)"); return } }
}

private let full = ["Ana", "Uva"]

// MARK: - Entering scoring

@Test func blankAnswersAutoScoreZero() throws {
    var (s, ids) = try writingGame()
    try collect(&s, ids, [full, ["", "Uva"], ["  ", "\n"]])
    #expect(s.phase == .scoring(categoryIndex: 0, completed: false))
    let scores = try #require(s.currentRound?.scores)
    #expect(scores[ids[0]] == [nil, nil])
    #expect(scores[ids[1]] == [0, nil])
    #expect(scores[ids[2]] == [0, 0])
}

@Test func missingAnswersAutoScoreZero() throws {
    var (s, ids) = try writingGame()
    #expect(GameEngine.setPresence(.away, for: ids[2], in: &s))
    try collect(&s, ids, [full, full, nil])
    #expect(s.phase == .scoring(categoryIndex: 0, completed: false))
    #expect(s.currentRound?.scores[ids[2]] == [0, 0])
}

@Test func whitespaceAnswerCannotScoreFive() throws {
    var (s, ids) = try writingGame()
    try collect(&s, ids, [full, ["  ", "Uva"], full])
    let before = s
    #expect(throws: GameError.invalidScore) { try score(&s, ids[1], category: 0, points: 5) }
    #expect(throws: GameError.invalidScore) { try score(&s, ids[1], category: 0, points: 10) }
    #expect(throws: GameError.invalidScore) { try score(&s, ids[0], category: 0, points: 7) }
    #expect(s == before)
    try score(&s, ids[1], category: 0, points: 0)  // already 0: no-op
    #expect(s == before)
}

@Test func playerCanOnlyScoreSelf() throws {
    var (s, ids) = try writingGame()
    try collect(&s, ids, [full, full, full])
    #expect(throws: GameError.cannotScoreForOthers) { try score(&s, ids[1], category: 0, points: 10, for: ids[2]) }
    try score(&s, ids[1], category: 0, points: 10)
    #expect(s.currentRound?.scores[ids[1]] == [10, nil])
}

@Test func hostCanScoreForAwayPlayer() throws {
    var (s, ids) = try writingGame()
    try collect(&s, ids, [full, full, full])
    #expect(GameEngine.setPresence(.away, for: ids[2], in: &s))
    try score(&s, ids[0], category: 0, points: 5, for: ids[2])
    #expect(s.currentRound?.scores[ids[2]] == [5, nil])
    #expect(throws: GameError.cannotScoreForOthers) { try score(&s, ids[1], category: 0, points: 10, for: ids[2]) }
}

@Test func hostCannotScoreForPresentPlayer() throws {
    var (s, ids) = try writingGame()
    try collect(&s, ids, [full, full, full])
    #expect(throws: GameError.cannotScoreForOthers) { try score(&s, ids[0], category: 0, points: 10, for: ids[1]) }
}

@Test func setScoreValidatesRoundPhaseAndCategory() throws {
    var (s, ids) = try writingGame()
    #expect(throws: GameError.wrongPhase) { try score(&s, ids[1], category: 0, points: 10) }
    try collect(&s, ids, [full, full, full])
    #expect(throws: GameError.wrongPhase) { try score(&s, ids[1], category: 1, points: 10) }
    #expect(throws: GameError.staleRound) {
        try send(.setScore(round: 2, category: 0, points: 10, player: ids[1]), ids[1], &s)
    }
}

@Test func scoreCanChangeUntilCategoryCompletes() throws {
    var (s, ids) = try writingGame()
    try collect(&s, ids, [full, full, full])
    let v = s.version
    try score(&s, ids[1], category: 0, points: 10)
    try score(&s, ids[1], category: 0, points: 5)
    #expect(s.version == v + 2)
    #expect(s.currentRound?.scores[ids[1]] == [5, nil])
    try score(&s, ids[0], category: 0, points: 10)
    try score(&s, ids[2], category: 0, points: 0)
    #expect(s.phase == .scoring(categoryIndex: 0, completed: true))
    #expect(throws: GameError.wrongPhase) { try score(&s, ids[1], category: 0, points: 10) }
    #expect(s.currentRound?.scores[ids[1]] == [5, nil])
}

// MARK: - Category completion and advancing

@Test func categoryCompletesWhenAllActiveScored() throws {
    var (s, ids) = try writingGame()
    try collect(&s, ids, [full, full, full])
    try score(&s, ids[0], category: 0, points: 10)
    try score(&s, ids[1], category: 0, points: 5)
    #expect(s.phase == .scoring(categoryIndex: 0, completed: false))
    let v = s.version
    try score(&s, ids[2], category: 0, points: 5)
    #expect(s.phase == .scoring(categoryIndex: 0, completed: true))
    #expect(s.version == v + 1)
}

@Test func tickAdvancesToNextCategory() throws {
    var (s, ids) = try writingGame()
    try collect(&s, ids, [full, ["Asno", ""], full])
    for id in ids { try score(&s, id, category: 0, points: 10) }
    let v = s.version
    #expect(GameEngine.tick(&s))
    #expect(s.phase == .scoring(categoryIndex: 1, completed: false))
    #expect(s.version == v + 1)
    #expect(!GameEngine.tick(&s))  // incomplete category does not advance
}

@Test func tickSkipsAlreadyCompleteCategory() throws {
    var (s, ids) = try writingGame()
    try collect(&s, ids, [["Ana", ""], ["Asno", " "], ["Arara", ""]])
    for id in ids { try score(&s, id, category: 0, points: 10) }
    #expect(GameEngine.tick(&s))
    #expect(s.phase == .scoring(categoryIndex: 1, completed: true))
}

@Test func lastCategoryTickGoesToRoundResults() throws {
    var (s, ids) = try writingGame()
    try collect(&s, ids, [full, full, full])
    for c in 0..<2 {
        for id in ids { try score(&s, id, category: c, points: 5) }
        #expect(GameEngine.tick(&s))
    }
    #expect(s.phase == .roundResults)
    #expect(!GameEngine.tick(&s))
    #expect(s.totals == [ids[0]: 10, ids[1]: 10, ids[2]: 10])
}

@Test func leftPlayersSkippedAndZeroed() throws {
    var (s, ids) = try writingGame()
    try collect(&s, ids, [full, full, full])
    try send(.leave, ids[2], &s)
    try score(&s, ids[0], category: 0, points: 10)
    try score(&s, ids[1], category: 0, points: 10)
    #expect(s.phase == .scoring(categoryIndex: 0, completed: true))
    #expect(s.currentRound?.scores[ids[2]] == [0, nil])
    #expect(GameEngine.tick(&s))
    try score(&s, ids[0], category: 1, points: 5)
    try score(&s, ids[1], category: 1, points: 5)
    #expect(s.currentRound?.scores[ids[2]] == [0, 0])
    #expect(s.totals[ids[2]] == 0)
}

@Test func lateAnswersFillOnlyUnscoredCategories() throws {
    var (s, ids) = try writingGame(categories: ["Animal", "Fruta", "Lugar"])
    #expect(GameEngine.setPresence(.away, for: ids[2], in: &s))
    try collect(&s, ids, [["Ana", "Uva", "Rio"], ["Asno", "Abacate", "Roma"], nil])
    #expect(s.currentRound?.scores[ids[2]] == [0, 0, 0])
    try score(&s, ids[0], category: 0, points: 10)
    try score(&s, ids[1], category: 0, points: 10)
    #expect(GameEngine.tick(&s))
    #expect(s.phase == .scoring(categoryIndex: 1, completed: false))
    #expect(GameEngine.setPresence(.present, for: ids[2], in: &s))
    let late = ["Arara", "Banana", " "]
    try send(.submitAnswers(round: 1, answers: late), ids[2], &s)
    #expect(s.currentRound?.answers[ids[2]] == late)
    #expect(s.currentRound?.scores[ids[2]] == [0, nil, 0])
    #expect(s.phase == .scoring(categoryIndex: 1, completed: false))
    try score(&s, ids[2], category: 1, points: 10)
}

@Test func lateAnswersAfterCompletionLeaveCurrentCategory() throws {
    var (s, ids) = try writingGame(categories: ["Animal", "Fruta", "Lugar"])
    #expect(GameEngine.setPresence(.away, for: ids[2], in: &s))
    try collect(&s, ids, [["Ana", "Uva", "Rio"], ["Asno", "Abacate", "Roma"], nil])
    try score(&s, ids[0], category: 0, points: 10)
    try score(&s, ids[1], category: 0, points: 10)
    #expect(s.phase == .scoring(categoryIndex: 0, completed: true))
    try send(.submitAnswers(round: 1, answers: ["Arara", "Banana", "Recife"]), ids[2], &s)
    #expect(s.currentRound?.scores[ids[2]] == [0, nil, nil])
    #expect(s.phase == .scoring(categoryIndex: 0, completed: true))
}

// MARK: - Results, next round, end game

@Test func totalsAccumulateAcrossRounds() throws {
    var (s, ids) = try writingGame(players: 2)
    try collect(&s, ids, [full, full])
    for c in 0..<2 {
        try score(&s, ids[0], category: c, points: 10)
        try score(&s, ids[1], category: c, points: 5)
        #expect(GameEngine.tick(&s))
    }
    #expect(s.phase == .roundResults)
    try send(.nextRound, ids[0], &s)
    tickToWriting(&s)
    try collect(&s, ids, [full, ["Asno", ""]])
    try score(&s, ids[0], category: 0, points: 5)
    try score(&s, ids[1], category: 0, points: 10)
    #expect(GameEngine.tick(&s))
    try score(&s, ids[0], category: 1, points: 0)
    #expect(GameEngine.tick(&s))
    #expect(s.phase == .roundResults)
    #expect(s.totals == [ids[0]: 25, ids[1]: 20])
}

@Test func nextRoundNeverRepeatsLetters() throws {
    var (s, ids) = try writingGame(players: 2)
    try playBlankRound(&s, ids)
    for seed in 1..<26 {
        try send(.nextRound, ids[0], &s, seed: UInt64(seed))
        tickToWriting(&s)
        try playBlankRound(&s, ids)
    }
    #expect(s.rounds.count == 26)
    #expect(Set(s.rounds.map(\.letter)).count == 26)
    #expect(s.rounds.map(\.number) == Array(1...26))
}

@Test func nextRoundIncludesAwayButNotLeft() throws {
    var (s, ids) = try writingGame(players: 5)
    try playBlankRound(&s, ids)
    #expect(GameEngine.setPresence(.away, for: ids[2], in: &s))
    try send(.leave, ids[3], &s)
    try send(.removePlayer(ids[4]), ids[0], &s)
    #expect(throws: GameError.notHost) { try send(.nextRound, ids[1], &s) }
    let v = s.version
    try send(.nextRound, ids[0], &s)
    #expect(s.version == v + 1)
    #expect(s.phase == .revealing(ticksRemaining: 2))
    #expect(s.currentRound?.number == 2)
    #expect(s.currentRound?.participants == [ids[0], ids[1], ids[2]])
    #expect(s.usedLetters.count == 2)
    #expect(throws: GameError.wrongPhase) { try send(.nextRound, ids[0], &s) }
}

@Test func endGameFromAnyPhase() throws {
    var (lobby, _) = try writingGame()
    lobby.phase = .lobby
    let (writing, ids) = try writingGame()
    var scoring = writing
    try collect(&scoring, ids, [full, full, full])
    var results = writing
    try playBlankRound(&results, ids)
    for var s in [lobby, writing, scoring, results] {
        let host = s.hostID
        #expect(throws: GameError.notHost) { try send(.endGame, s.players[1].id, &s) }
        let v = s.version
        try send(.endGame, host, &s)
        #expect(s.phase == .gameOver)
        #expect(s.version == v + 1)
        try send(.endGame, host, &s)
        #expect(s.version == v + 1)
    }
}

// MARK: - Presence and participant changes

@Test func presenceChangeUnblocksScoring() throws {
    var (s, ids) = try writingGame(players: 4)
    try collect(&s, ids, [full, full, full, full])
    try score(&s, ids[0], category: 0, points: 10)
    try score(&s, ids[1], category: 0, points: 10)
    #expect(GameEngine.setPresence(.away, for: ids[2], in: &s))
    #expect(s.phase == .scoring(categoryIndex: 0, completed: false))  // away still needs a score
    try send(.leave, ids[2], &s)
    #expect(s.phase == .scoring(categoryIndex: 0, completed: false))  // ids[3] still unscored
    let v = s.version
    try send(.removePlayer(ids[3]), ids[0], &s)
    #expect(s.version == v + 1)
    #expect(s.phase == .scoring(categoryIndex: 0, completed: true))
    #expect(s.currentRound?.scores[ids[2]] == [0, nil])
    #expect(s.currentRound?.scores[ids[3]] == [0, nil])
}

@Test func leavingLastNeededStopperLocksRound() throws {
    var (s, ids) = try writingGame(players: 3, stopsRequired: 3)
    try send(.stop(answers: full), ids[0], &s)
    try send(.stop(answers: full), ids[1], &s)
    #expect(s.phase == .writing)
    let v = s.version
    try send(.leave, ids[2], &s)
    #expect(s.version == v + 1)
    // Locked at 2 stops; nobody present is waiting, so scoring begins.
    #expect(s.phase == .scoring(categoryIndex: 0, completed: false))
}

@Test func removingLastNeededStopperLocksRound() throws {
    var (s, ids) = try writingGame(players: 4, stopsRequired: 3)
    try send(.stop(answers: full), ids[0], &s)
    try send(.stop(answers: full), ids[1], &s)
    try send(.leave, ids[1], &s)  // their stop still counts
    #expect(s.phase == .writing)
    try send(.removePlayer(ids[3]), ids[0], &s)
    #expect(s.phase == .collecting)  // ids[2] (present) still owes answers
    try send(.submitAnswers(round: 1, answers: full), ids[2], &s)
    #expect(s.phase == .scoring(categoryIndex: 0, completed: false))
}

@Test func lastWaitingPlayerGoingAwayStartsScoring() throws {
    var (s, ids) = try writingGame(players: 3, stopsRequired: 1)
    try send(.stop(answers: full), ids[0], &s)
    try send(.submitAnswers(round: 1, answers: full), ids[1], &s)
    #expect(s.phase == .collecting)
    let v = s.version
    #expect(GameEngine.setPresence(.away, for: ids[2], in: &s))
    #expect(s.version == v + 1)
    #expect(s.phase == .scoring(categoryIndex: 0, completed: false))
    #expect(s.currentRound?.scores[ids[2]] == [0, 0])
}

@Test func lastWaitingPlayerLeavingStartsScoring() throws {
    var (s, ids) = try writingGame(players: 3, stopsRequired: 1)
    try send(.stop(answers: full), ids[0], &s)
    try send(.submitAnswers(round: 1, answers: full), ids[1], &s)
    try send(.leave, ids[2], &s)
    #expect(s.phase == .scoring(categoryIndex: 0, completed: false))
}

@Test func setPresenceTogglesPresentAndAwayOnly() throws {
    var (s, ids) = try writingGame(players: 4)
    let v = s.version
    #expect(GameEngine.setPresence(.away, for: ids[1], in: &s))
    #expect(s.player(ids[1])?.presence == .away && s.version == v + 1)
    #expect(!GameEngine.setPresence(.away, for: ids[1], in: &s))
    #expect(s.version == v + 1)
    #expect(GameEngine.setPresence(.present, for: ids[1], in: &s))
    #expect(s.player(ids[1])?.presence == .present && s.version == v + 2)
    #expect(!GameEngine.setPresence(.present, for: ids[1], in: &s))
    #expect(!GameEngine.setPresence(.left, for: ids[1], in: &s))
    #expect(!GameEngine.setPresence(.away, for: UUID(), in: &s))
    #expect(s.version == v + 2)
}

@Test func setPresenceDoesNotOverrideLeft() throws {
    var (s, ids) = try writingGame(players: 4)
    try send(.leave, ids[2], &s)
    try send(.removePlayer(ids[3]), ids[0], &s)
    let before = s
    for p in [Presence.present, .away] {
        #expect(!GameEngine.setPresence(p, for: ids[2], in: &s))
        #expect(!GameEngine.setPresence(p, for: ids[3], in: &s))
    }
    #expect(s == before)
}
