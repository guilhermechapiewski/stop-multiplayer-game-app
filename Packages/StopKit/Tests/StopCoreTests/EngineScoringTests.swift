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

/// The host moves past the current (completed) scoring category.
private func next(_ s: inout GameState) throws {
    guard case .scoring(let category, _) = s.phase else { Issue.record("not scoring: \(s.phase)"); return }
    try send(.nextCategory(round: s.currentRound?.number ?? 0, category: category), s.hostID, &s)
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

/// Everyone submits blanks, so every category completes at once; the host advances to `.roundResults`.
private func playBlankRound(_ s: inout GameState, _ ids: [PlayerID]) throws {
    let blank = Array(repeating: "", count: s.settings.categories.count)
    try collect(&s, ids, ids.map { _ in blank })
    while s.phase != .roundResults { try next(&s) }
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

@Test func setScoreInLobbyIsWrongPhase() throws {
    var (s, ids) = try writingGame()
    s.phase = .lobby
    s.rounds = []
    #expect(throws: GameError.wrongPhase) {
        try send(.setScore(round: 1, category: 0, points: 10, player: ids[1]), ids[1], &s)
    }
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

@Test func scoreCanChangeUntilHostAdvances() throws {
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
    // Completed but not yet advanced: a wrong pick can still be corrected, and the category stays completed.
    let completedVersion = s.version
    try score(&s, ids[1], category: 0, points: 10)
    #expect(s.version == completedVersion + 1)
    #expect(s.currentRound?.scores[ids[1]] == [10, nil])
    #expect(s.phase == .scoring(categoryIndex: 0, completed: true))
    #expect(throws: GameError.cannotScoreForOthers) { try score(&s, ids[1], category: 0, points: 0, for: ids[2]) }
    try next(&s)
    #expect(throws: GameError.wrongPhase) { try score(&s, ids[1], category: 0, points: 5) }
    #expect(s.currentRound?.scores[ids[1]] == [10, nil])
}

@Test func hostCanCorrectAwayPlayersScoreWhileCompleted() throws {
    var (s, ids) = try writingGame()
    try collect(&s, ids, [full, full, full])
    #expect(GameEngine.setPresence(.away, for: ids[2], in: &s))
    try score(&s, ids[0], category: 0, points: 10)
    try score(&s, ids[1], category: 0, points: 10)
    try score(&s, ids[0], category: 0, points: 10, for: ids[2])
    #expect(s.phase == .scoring(categoryIndex: 0, completed: true))
    try score(&s, ids[0], category: 0, points: 5, for: ids[2])
    #expect(s.currentRound?.scores[ids[2]] == [5, nil])
    #expect(s.phase == .scoring(categoryIndex: 0, completed: true))
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

@Test func tickNeverAdvancesScoring() throws {
    var (s, ids) = try writingGame()
    try collect(&s, ids, [full, full, full])
    for id in ids { try score(&s, id, category: 0, points: 10) }
    #expect(s.phase == .scoring(categoryIndex: 0, completed: true))
    let before = s
    #expect(!GameEngine.tick(&s))
    #expect(s == before)
}

@Test func nextCategoryAdvancesToNextCategory() throws {
    var (s, ids) = try writingGame()
    try collect(&s, ids, [full, ["Asno", ""], full])
    for id in ids { try score(&s, id, category: 0, points: 10) }
    let v = s.version
    try send(.nextCategory(round: 1, category: 0), ids[0], &s)
    #expect(s.phase == .scoring(categoryIndex: 1, completed: false))
    #expect(s.version == v + 1)
}

@Test func nextCategoryIsHostOnly() throws {
    var (s, ids) = try writingGame()
    try collect(&s, ids, [full, full, full])
    for id in ids { try score(&s, id, category: 0, points: 10) }
    let before = s
    #expect(throws: GameError.notHost) { try send(.nextCategory(round: 1, category: 0), ids[1], &s) }
    #expect(s == before)
}

@Test func nextCategoryOnlyWhenCompleted() throws {
    var (s, ids) = try writingGame()
    #expect(throws: GameError.wrongPhase) { try send(.nextCategory(round: 1, category: 0), ids[0], &s) }
    try collect(&s, ids, [full, full, full])
    try score(&s, ids[0], category: 0, points: 10)
    let before = s
    #expect(throws: GameError.wrongPhase) { try send(.nextCategory(round: 1, category: 0), ids[0], &s) }
    #expect(s == before)
}

@Test func nextCategoryRejectsStaleOrDuplicateRequests() throws {
    var (s, ids) = try writingGame(categories: ["Animal", "Fruta", "Lugar"])
    try collect(&s, ids, [["Ana", "Uva", "Rio"], ["Asno", "Abacate", "Roma"], ["Arara", "Amora", "Acre"]])
    for id in ids { try score(&s, id, category: 0, points: 10) }
    #expect(throws: GameError.staleRound) { try send(.nextCategory(round: 2, category: 0), ids[0], &s) }
    #expect(throws: GameError.wrongPhase) { try send(.nextCategory(round: 1, category: 1), ids[0], &s) }
    try send(.nextCategory(round: 1, category: 0), ids[0], &s)
    for id in ids { try score(&s, id, category: 1, points: 5) }
    #expect(s.phase == .scoring(categoryIndex: 1, completed: true))
    // A retried "next" for category 0 must not skip category 1.
    let before = s
    #expect(throws: GameError.wrongPhase) { try send(.nextCategory(round: 1, category: 0), ids[0], &s) }
    #expect(s == before)
}

@Test func nextCategoryLandsOnPreCompletedCategory() throws {
    var (s, ids) = try writingGame()
    try collect(&s, ids, [["Ana", ""], ["Asno", " "], ["Arara", ""]])
    for id in ids { try score(&s, id, category: 0, points: 10) }
    try next(&s)
    #expect(s.phase == .scoring(categoryIndex: 1, completed: true))
}

@Test func nextCategoryAfterLastGoesToRoundResults() throws {
    var (s, ids) = try writingGame()
    try collect(&s, ids, [full, full, full])
    for c in 0..<2 {
        for id in ids { try score(&s, id, category: c, points: 5) }
        try next(&s)
    }
    #expect(s.phase == .roundResults)
    #expect(throws: GameError.wrongPhase) { try send(.nextCategory(round: 1, category: 1), ids[0], &s) }
    #expect(s.totals == [ids[0]: 10, ids[1]: 10, ids[2]: 10])
}

/// The host goes back one category from the current scoring category (or from the results).
private func previous(_ s: inout GameState) throws {
    let category: Int
    switch s.phase {
    case .scoring(let current, _): category = current
    case .roundResults: category = s.settings.categories.count
    default: Issue.record("can't go back from \(s.phase)"); return
    }
    try send(.previousCategory(round: s.currentRound?.number ?? 0, category: category), s.hostID, &s)
}

private let three = ["Animal", "Fruta", "Lugar"]
private let threeAnswers = [["Ana", "Uva", "Rio"], ["Asno", "Abacate", "Roma"], ["Arara", "Amora", "Acre"]]

@Test func previousCategoryGoesBackOneCategory() throws {
    var (s, ids) = try writingGame(categories: three)
    try collect(&s, ids, threeAnswers)
    for id in ids { try score(&s, id, category: 0, points: 10) }
    try next(&s)
    #expect(s.phase == .scoring(categoryIndex: 1, completed: false))
    let v = s.version
    try previous(&s)
    #expect(s.phase == .scoring(categoryIndex: 0, completed: true))
    #expect(s.version == v + 1)
    // Category 0's scores stay editable, and going forward again lands on category 1 as it was left.
    try score(&s, ids[1], category: 0, points: 5)
    #expect(s.phase == .scoring(categoryIndex: 0, completed: true))
    try next(&s)
    #expect(s.phase == .scoring(categoryIndex: 1, completed: false))
    #expect(s.totals[ids[1]] == 5)
}

@Test func previousCategoryIsHostOnly() throws {
    var (s, ids) = try writingGame(categories: three)
    try collect(&s, ids, threeAnswers)
    for id in ids { try score(&s, id, category: 0, points: 10) }
    try next(&s)
    let before = s
    #expect(throws: GameError.notHost) { try send(.previousCategory(round: 1, category: 1), ids[1], &s) }
    #expect(s == before)
}

@Test func previousCategoryGuardsPhaseRoundAndCategory() throws {
    var (s, ids) = try writingGame(categories: three)
    #expect(throws: GameError.wrongPhase) { try send(.previousCategory(round: 1, category: 1), ids[0], &s) }
    try collect(&s, ids, threeAnswers)
    // Nothing before the first category.
    #expect(throws: GameError.wrongPhase) { try send(.previousCategory(round: 1, category: 0), ids[0], &s) }
    for id in ids { try score(&s, id, category: 0, points: 10) }
    try next(&s)
    let before = s
    #expect(throws: GameError.staleRound) { try send(.previousCategory(round: 2, category: 1), ids[0], &s) }
    #expect(throws: GameError.wrongPhase) { try send(.previousCategory(round: 1, category: 2), ids[0], &s) }
    #expect(s == before)
}

@Test func repeatedPreviousCategoryNeverMovesTwice() throws {
    var (s, ids) = try writingGame(categories: three)
    try collect(&s, ids, threeAnswers)
    for c in 0..<2 {
        for id in ids { try score(&s, id, category: c, points: 10) }
        try next(&s)
    }
    #expect(s.phase == .scoring(categoryIndex: 2, completed: false))
    try send(.previousCategory(round: 1, category: 2), ids[0], &s)
    #expect(s.phase == .scoring(categoryIndex: 1, completed: true))
    let before = s
    #expect(throws: GameError.wrongPhase) { try send(.previousCategory(round: 1, category: 2), ids[0], &s) }
    #expect(s == before)
}

@Test func backFromResultsReopensTheLastCategoryForCorrections() throws {
    var (s, ids) = try writingGame(categories: three)
    try collect(&s, ids, threeAnswers)
    for c in 0..<3 {
        for id in ids { try score(&s, id, category: c, points: 10) }
        try next(&s)
    }
    #expect(s.phase == .roundResults)
    #expect(s.totals[ids[1]] == 30)
    // Only "back from results" (the category count) is accepted there.
    #expect(throws: GameError.wrongPhase) { try send(.previousCategory(round: 1, category: 2), ids[0], &s) }
    try previous(&s)
    #expect(s.phase == .scoring(categoryIndex: 2, completed: true))
    #expect(throws: GameError.wrongPhase) { try send(.previousCategory(round: 1, category: 3), ids[0], &s) }
    try previous(&s)
    #expect(s.phase == .scoring(categoryIndex: 1, completed: true))
    // A player corrects their score; the totals follow.
    try score(&s, ids[1], category: 1, points: 5)
    #expect(s.totals[ids[1]] == 25)
    try next(&s)
    try next(&s)
    #expect(s.phase == .roundResults)
    #expect(s.totals == [ids[0]: 30, ids[1]: 25, ids[2]: 30])
}

@Test func earlierRoundsAreFinalOnceTheNextRoundStarts() throws {
    var (s, ids) = try writingGame()
    try playBlankRound(&s, ids)
    try send(.nextRound, ids[0], &s)
    let before = s
    #expect(throws: GameError.staleRound) { try send(.previousCategory(round: 1, category: 2), ids[0], &s) }
    #expect(throws: GameError.wrongPhase) { try send(.previousCategory(round: 2, category: 2), ids[0], &s) }
    #expect(s == before)
}

@Test func hostCanStillScoreForAwayPlayerAfterGoingBack() throws {
    var (s, ids) = try writingGame(categories: three)
    try collect(&s, ids, threeAnswers)
    for id in ids { try score(&s, id, category: 0, points: 10) }
    try next(&s)
    #expect(GameEngine.setPresence(.away, for: ids[2], in: &s))
    try previous(&s)
    try score(&s, ids[0], category: 0, points: 0, for: ids[2])
    #expect(s.currentRound?.scores[ids[2]]?[0] == 0)
    #expect(throws: GameError.cannotScoreForOthers) { try score(&s, ids[0], category: 0, points: 5, for: ids[1]) }
}

@Test func lateAnswersAfterGoingBackLeaveCompletedCategoriesOnly() throws {
    var (s, ids) = try writingGame(categories: ["Animal", "Fruta", "Lugar", "Cor"])
    #expect(GameEngine.setPresence(.away, for: ids[2], in: &s))
    try collect(&s, ids, [["Ana", "Uva", "Rio", "Azul"], ["Asno", "Abacate", "Roma", "Anil"], nil])
    for c in 0..<2 {
        try score(&s, ids[0], category: c, points: 10)
        try score(&s, ids[1], category: c, points: 10)
        try next(&s)
    }
    #expect(s.phase == .scoring(categoryIndex: 2, completed: false))
    try previous(&s)
    try previous(&s)
    #expect(s.phase == .scoring(categoryIndex: 0, completed: true))
    #expect(GameEngine.setPresence(.present, for: ids[2], in: &s))
    try send(.submitAnswers(round: 1, answers: ["Arara", "Amora", "Acre", "Amarelo"]), ids[2], &s)
    // Categories 0 and 1 were completed already; category 2 was reached but left unfinished, so the late
    // answer still gets scored there, like the last one.
    #expect(s.currentRound?.scores[ids[2]] == [0, 0, nil, nil])
}

@Test func lateAnswersAfterGoingBackFromACompletedCategoryLeaveIt() throws {
    var (s, ids) = try writingGame(categories: ["Animal", "Fruta", "Lugar", "Cor"])
    #expect(GameEngine.setPresence(.away, for: ids[2], in: &s))
    try collect(&s, ids, [["Ana", "Uva", "Rio", "Azul"], ["Asno", "Abacate", "Roma", "Anil"], nil])
    for c in 0..<3 {
        try score(&s, ids[0], category: c, points: 10)
        try score(&s, ids[1], category: c, points: 10)
        if c < 2 { try next(&s) }
    }
    #expect(s.phase == .scoring(categoryIndex: 2, completed: true))
    try previous(&s)
    #expect(GameEngine.setPresence(.present, for: ids[2], in: &s))
    try send(.submitAnswers(round: 1, answers: ["Arara", "Amora", "Acre", "Amarelo"]), ids[2], &s)
    // Category 2 was completed before the host went back, so its 0 stands.
    #expect(s.currentRound?.scores[ids[2]] == [0, 0, 0, nil])
}

@Test func leftPlayersSkippedAndZeroed() throws {
    var (s, ids) = try writingGame()
    try collect(&s, ids, [full, full, full])
    try send(.leave, ids[2], &s)
    try score(&s, ids[0], category: 0, points: 10)
    try score(&s, ids[1], category: 0, points: 10)
    #expect(s.phase == .scoring(categoryIndex: 0, completed: true))
    #expect(s.currentRound?.scores[ids[2]] == [0, nil])
    try next(&s)
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
    try next(&s)
    #expect(s.phase == .scoring(categoryIndex: 1, completed: false))
    #expect(GameEngine.setPresence(.present, for: ids[2], in: &s))
    let late = ["Arara", "Banana", " "]
    try send(.submitAnswers(round: 1, answers: late), ids[2], &s)
    #expect(s.currentRound?.answers[ids[2]] == late)
    #expect(s.currentRound?.scores[ids[2]] == [0, nil, 0])
    #expect(s.phase == .scoring(categoryIndex: 1, completed: false))
    try score(&s, ids[2], category: 1, points: 10)
    #expect(s.currentRound?.scores[ids[2]] == [0, 10, 0])
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
        try next(&s)
    }
    #expect(s.phase == .roundResults)
    try send(.nextRound, ids[0], &s)
    tickToWriting(&s)
    try collect(&s, ids, [full, ["Asno", ""]])
    try score(&s, ids[0], category: 0, points: 5)
    try score(&s, ids[1], category: 0, points: 10)
    try next(&s)
    try score(&s, ids[0], category: 1, points: 0)
    try next(&s)
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

// MARK: - Left/removed players rejoining mid-round come back from the next round

@Test func rejoinedPlayerDoesNotCountTowardStopsRequired() throws {
    var (s, ids) = try writingGame(players: 3, stopsRequired: 3)
    try send(.leave, ids[2], &s)
    let v = s.version
    try send(.join(name: "P2"), ids[2], &s)
    #expect(s.version == v + 1)
    #expect(s.player(ids[2])?.presence == .present)
    #expect(s.currentRound?.participants == [ids[0], ids[1]])
    try send(.stop(answers: full), ids[0], &s)
    try send(.stop(answers: full), ids[1], &s)
    #expect(s.phase == .scoring(categoryIndex: 0, completed: false))
    #expect(throws: GameError.notParticipant) { try score(&s, ids[2], category: 0, points: 10) }
}

@Test func rejoinedPlayerDoesNotBlockCollecting() throws {
    var (s, ids) = try writingGame(players: 3, stopsRequired: 1)
    try send(.removePlayer(ids[2]), ids[0], &s)
    try send(.join(name: "P2"), ids[2], &s)
    try send(.stop(answers: full), ids[0], &s)
    #expect(s.phase == .collecting)
    try send(.submitAnswers(round: 1, answers: full), ids[1], &s)
    #expect(s.phase == .scoring(categoryIndex: 0, completed: false))
}

@Test func rejoinedPlayerDoesNotBlockCategoryCompletion() throws {
    var (s, ids) = try writingGame()
    try collect(&s, ids, [full, full, ["Asno", ""]])
    try send(.leave, ids[2], &s)
    try send(.join(name: "P2"), ids[2], &s)
    try score(&s, ids[0], category: 0, points: 10)
    try score(&s, ids[1], category: 0, points: 10)
    #expect(s.phase == .scoring(categoryIndex: 0, completed: true))
    // Already-recorded answers and scores are kept.
    #expect(s.currentRound?.answers[ids[2]] == ["Asno", ""])
    #expect(s.currentRound?.scores[ids[2]] == [nil, 0])
}

@Test func rejoinedPlayerIsParticipantInNextRound() throws {
    var (s, ids) = try writingGame()
    try send(.leave, ids[2], &s)
    try send(.join(name: "P2"), ids[2], &s)
    try playBlankRound(&s, Array(ids.prefix(2)))  // ids[2] sits this round out
    try send(.nextRound, ids[0], &s)
    #expect(s.currentRound?.participants == ids)
}

@Test func rejoinBetweenRoundsKeepsParticipantsUntouched() throws {
    var (s, ids) = try writingGame()
    try playBlankRound(&s, ids)
    try send(.leave, ids[2], &s)
    try send(.join(name: "P2"), ids[2], &s)
    #expect(s.currentRound?.participants == ids)
}
