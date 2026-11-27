import Foundation
import Testing
@testable import StopCore

private let a = UUID(), b = UUID(), c = UUID()

private func state(_ phase: Phase) -> GameState {
    let round = Round(number: 1, letter: "A", participants: [a, b, c],
                      answers: [a: ["Ana", "Uva"], b: ["Asno", "Abacate"]])
    return GameState(gameID: UUID(), hostID: a, version: 4, language: .en,
                     settings: GameSettings(categories: ["Animal", "Fruta"], stopsRequired: 1, allowGiveUp: false),
                     players: [Player(id: a, name: "A", presence: .present),
                               Player(id: b, name: "B", presence: .present),
                               Player(id: c, name: "C", presence: .present)],
                     phase: phase, rounds: [Round(number: 0, letter: "Z", participants: [a, b],
                                                  answers: [a: ["Zebra"], b: ["Zimbro"]]), round],
                     usedLetters: ["Z", "A"])
}

@Test func redactionHidesOthersAnswersUntilScoring() {
    let hidden: [Phase] = [.revealing(ticksRemaining: 2), .countdown(secondsRemaining: 1), .writing, .collecting]
    for phase in hidden {
        let s = state(phase)
        let forB = s.redacted(for: b)
        // Own entry intact; others' keys kept (who has sent answers) with their values emptied.
        #expect(forB.currentRound?.answers == [a: [], b: ["Asno", "Abacate"]])
        // A viewer with no answers of their own sees only who has sent theirs.
        #expect(s.redacted(for: c).currentRound?.answers == [a: [], b: []])
        // Everything else is untouched, including earlier rounds.
        var expected = s
        expected.rounds[1].answers = [a: [], b: ["Asno", "Abacate"]]
        #expect(forB == expected)
    }
}

@Test func redactionNeverRevealsBlankness() {
    for phase in [Phase.writing, .collecting] {
        var s = state(phase)
        s.rounds[1].answers[c] = ["", "  "]
        let forB = s.redacted(for: b)
        #expect(forB.currentRound?.answers[a] == [])
        #expect(forB.currentRound?.answers[c] == [])
        #expect(s.redacted(for: c).currentRound?.answers[c] == ["", "  "])
    }
}

@Test func redactionShowsAllOutsideRoundsAndInSilentScoring() {
    for phase in [Phase.lobby, .roundResults, .gameOver] {
        let s = state(phase)
        #expect(s.redacted(for: b) == s)
    }
    for phase in [Phase.scoring(categoryIndex: 0, completed: false), .scoring(categoryIndex: 1, completed: true)] {
        var s = state(phase)
        s.settings.silentScoring = true
        s.rounds[1].scores = [a: [nil, nil], b: [nil, 5]]
        #expect(s.redacted(for: b) == s)
    }
}

/// Read-aloud scoring: a's answers scored as given, b's not scored at all.
private func readAloud(_ phase: Phase = .scoring(categoryIndex: 0, completed: false),
                       aScores: [Int?] = [10, nil]) -> GameState {
    var s = state(phase)
    s.rounds[1].scores = [a: aScores, b: [nil, nil]]
    return s
}

@Test func readAloudHidesAnswersUntilScored() {
    let s = readAloud()
    #expect(!s.settings.silentScoring)
    let forC = s.redacted(for: c)
    // Scored answers show; unscored ones are withheld as "" (a nil score means "hidden", never "blank").
    #expect(forC.currentRound?.answers == [a: ["Ana", ""], b: ["", ""]])
    // Scores, earlier rounds and everything else are untouched.
    var expected = s
    expected.rounds[1].answers = [a: ["Ana", ""], b: ["", ""]]
    #expect(forC == expected)
}

@Test func readAloudAlwaysShowsTheViewersOwnAnswers() {
    let s = readAloud()
    #expect(s.redacted(for: b).currentRound?.answers == [a: ["Ana", ""], b: ["Asno", "Abacate"]])
    #expect(s.redacted(for: a).currentRound?.answers == [a: ["Ana", "Uva"], b: ["", ""]])
}

@Test func readAloudRevealsAnAnswerOnceScored() {
    var s = readAloud(.scoring(categoryIndex: 1, completed: false), aScores: [10, 5])
    #expect(s.redacted(for: c).currentRound?.answers[a] == ["Ana", "Uva"])
    // The host scoring for an away player reveals it the same way.
    s.rounds[1].scores[b] = [0, nil]
    #expect(s.redacted(for: c).currentRound?.answers[b] == ["Asno", ""])
}

@Test func readAloudShowsTheHostTheAnswersOfPlayersAwayOrGone() {
    var s = readAloud()
    s.players[1].presence = .away
    // a is the host: it may score for b, so it sees b's answers; c (not the host) still doesn't.
    #expect(s.redacted(for: a).currentRound?.answers[b] == ["Asno", "Abacate"])
    #expect(s.redacted(for: c).currentRound?.answers[b] == ["", ""])
    s.players[1].presence = .left
    #expect(s.redacted(for: a).currentRound?.answers[b] == ["Asno", "Abacate"])
}

@Test func readAloudShowsEverythingInTheResults() {
    var s = readAloud()
    s.phase = .roundResults
    #expect(s.redacted(for: c) == s)
}

@Test func settingsWithoutSilentScoringDecodeAsReadAloud() throws {
    let old = #"{"categories":["Animal"],"stopsRequired":2,"allowGiveUp":true}"#
    let settings = try JSONDecoder().decode(GameSettings.self, from: Data(old.utf8))
    #expect(settings == GameSettings(categories: ["Animal"], stopsRequired: 2, allowGiveUp: true, silentScoring: false))
    let silent = GameSettings(categories: ["Animal"], stopsRequired: 1, allowGiveUp: false, silentScoring: true)
    #expect(try JSONDecoder().decode(GameSettings.self, from: JSONEncoder().encode(silent)) == silent)
}
