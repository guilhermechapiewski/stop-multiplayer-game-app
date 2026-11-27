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

@Test func redactionShowsAllDuringScoring() {
    let shown: [Phase] = [.lobby, .scoring(categoryIndex: 0, completed: false),
                          .scoring(categoryIndex: 1, completed: true), .roundResults, .gameOver]
    for phase in shown {
        let s = state(phase)
        #expect(s.redacted(for: b) == s)
    }
}
