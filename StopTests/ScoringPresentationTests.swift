import Foundation
import StopCore
import Testing
@testable import Stop

struct ScoringPresentationTests {
    let host = Player(id: UUID(), name: "Gui", presence: .present)
    let ana = Player(id: UUID(), name: "Ana", presence: .present)
    let bia = Player(id: UUID(), name: "Bia", presence: .away)
    let caio = Player(id: UUID(), name: "Caio", presence: .left)

    /// Scoring `category` of round 1 (letter B) with the given answers and scores; silent mode (every answer
    /// shown) unless `silent` is false.
    func makeState(players: [Player]? = nil, category: Int = 1, completed: Bool = false, silent: Bool = true,
                   answers: [PlayerID: [String]], scores: [PlayerID: [Int?]]) -> GameState {
        let players = players ?? [host, ana, bia, caio]
        return GameState(
            gameID: UUID(), hostID: host.id, version: 7, language: .en,
            settings: GameSettings(categories: ["Name", "Animal", "Country"], stopsRequired: 1, allowGiveUp: true,
                                   silentScoring: silent),
            players: players, phase: .scoring(categoryIndex: category, completed: completed),
            rounds: [Round(number: 1, letter: "B", participants: players.map(\.id),
                           stops: [StopRecord(playerID: ana.id, kind: .stop)], answers: answers, scores: scores)],
            usedLetters: ["B"])
    }

    var answers: [PlayerID: [String]] {
        [host.id: ["Bruno", "Bear", "Brazil"], ana.id: ["Bia", "  ", "Belgium"],
         bia.id: ["Beto", "Bee", "Bolivia"], caio.id: ["Bob", "Bat", "Benin"]]
    }

    @Test func presentationShowsDashForBlank() {
        var answers = answers
        answers[caio.id] = nil
        let state = makeState(answers: answers, scores: [host.id: [10, nil, nil], ana.id: [5, 0, nil],
                                                         bia.id: [nil, nil, nil], caio.id: [0, 0, 0]])
        let presentation = ScoringPresentation(state: state, viewer: ana.id)

        #expect(presentation.categoryName == "Animal")
        #expect(presentation.categoryIndex == 1)
        #expect(presentation.total == 3)
        #expect(presentation.rows.map(\.answer) == ["Bear", "—", "Bee", "—"])
        #expect(presentation.rows.map(\.isBlank) == [false, true, false, true])
        #expect(presentation.rows.map(\.score) == [nil, 0, nil, 0])
        #expect(presentation.rows.map(\.presence) == [.present, .present, .away, .left])
        #expect(presentation.myAnswerIsBlank)
        #expect(presentation.myScore == 0)
    }

    @Test func myScoreReflectsState() {
        let unscored = makeState(answers: answers, scores: [host.id: [10, nil, nil], ana.id: [5, 0, nil],
                                                            bia.id: [nil, nil, nil], caio.id: [nil, nil, nil]])
        let mine = ScoringPresentation(state: unscored, viewer: host.id)
        #expect(mine.myScore == nil)
        #expect(!mine.myAnswerIsBlank)

        let scored = makeState(answers: answers, scores: [host.id: [10, 5, nil], ana.id: [5, 0, nil],
                                                          bia.id: [nil, nil, nil], caio.id: [nil, nil, nil]])
        #expect(ScoringPresentation(state: scored, viewer: host.id).myScore == 5)

        // A player who joined after the round started isn't a participant: no answer or score of their own.
        let late = Player(id: UUID(), name: "Duda", presence: .present)
        var withLate = scored
        withLate.players.append(late)
        let latePresentation = ScoringPresentation(state: withLate, viewer: late.id)
        #expect(latePresentation.myScore == nil)
        #expect(latePresentation.rows.count == 4)
    }

    @Test func hostSeesScoreForAwayOnly() {
        let removed = Player(id: UUID(), name: "Duda", presence: .removed)
        let players = [host, ana, bia, caio, removed]
        var answers = answers
        answers[removed.id] = ["Bea", "Bull", "Bhutan"]
        let state = makeState(players: players, answers: answers,
                              scores: [host.id: [10, nil, nil], ana.id: [5, nil, nil], bia.id: [nil, nil, nil],
                                       caio.id: [nil, nil, nil], removed.id: [nil, nil, nil]])

        #expect(ScoringPresentation(state: state, viewer: host.id).canHostScore == [bia.id, caio.id])

        // Once scored, they no longer need the host.
        var scored = state
        scored.rounds[0].scores[bia.id] = [nil, 10, nil]
        #expect(ScoringPresentation(state: scored, viewer: host.id).canHostScore == [caio.id])
    }

    @Test func nonHostNeverSeesHostScoring() {
        let state = makeState(answers: answers, scores: [host.id: [10, nil, nil], ana.id: [5, nil, nil],
                                                         bia.id: [nil, nil, nil], caio.id: [nil, nil, nil]])
        #expect(ScoringPresentation(state: state, viewer: ana.id).canHostScore.isEmpty)
        #expect(ScoringPresentation(state: state, viewer: bia.id).canHostScore.isEmpty)
    }

    @Test func presentationUsesDisambiguatedNames() {
        let otherAna = Player(id: UUID(), name: "Ana", presence: .present)
        let players = [host, ana, otherAna]
        let state = makeState(players: players, answers: [:],
                              scores: [host.id: [0, 0, 0], ana.id: [0, 0, 0], otherAna.id: [0, 0, 0]])
        let presentation = ScoringPresentation(state: state, viewer: host.id)
        #expect(presentation.rows.map(\.name) == ["Gui", "Ana", "Ana 2"])
        #expect(presentation.rows.map(\.playerID) == players.map(\.id))
    }

    var allScored: [PlayerID: [Int?]] {
        [host.id: [10, 10, nil], ana.id: [5, 0, nil], bia.id: [nil, 5, nil], caio.id: [0, 0, nil]]
    }

    @Test func onlyTheHostAdvancesAndOnlyOnceComplete() {
        let open = makeState(answers: answers, scores: [host.id: [10, nil, nil], ana.id: [5, 0, nil],
                                                        bia.id: [nil, nil, nil], caio.id: [0, 0, nil]])
        let hostOpen = ScoringPresentation(state: open, viewer: host.id)
        #expect(hostOpen.showsAdvanceButton)
        #expect(!hostOpen.canAdvance)
        #expect(!hostOpen.isCompleted)

        let done = makeState(completed: true, answers: answers, scores: allScored)
        let hostDone = ScoringPresentation(state: done, viewer: host.id)
        #expect(hostDone.showsAdvanceButton && hostDone.canAdvance && hostDone.isCompleted)

        let anaDone = ScoringPresentation(state: done, viewer: ana.id)
        #expect(!anaDone.showsAdvanceButton)
        #expect(!anaDone.canAdvance)
        #expect(anaDone.isCompleted)
        #expect(anaDone.hostName == "Gui")
    }

    @Test func readAloudHidesUnscoredAnswersButTheViewersOwn() {
        // As the host's snapshot sends it to Ana: unscored answers of others withheld as "".
        let state = makeState(silent: false,
                              answers: [host.id: ["Bruno", "", "Brazil"], ana.id: ["Bia", "Bat", "Belgium"],
                                        bia.id: ["Beto", "", "Bolivia"], caio.id: ["Bob", "", "Benin"]],
                              scores: [host.id: [10, nil, nil], ana.id: [5, nil, nil], bia.id: [nil, nil, nil],
                                       caio.id: [0, 0, nil]])
        let presentation = ScoringPresentation(state: state, viewer: ana.id)
        #expect(presentation.isReadAloud)
        #expect(presentation.rows.map(\.isHidden) == [true, false, true, false])
        #expect(presentation.rows.map(\.answer) == ["", "Bat", "", "—"])
        // Hidden isn't blank, and has no score to show.
        #expect(presentation.rows[0].isBlank == false && presentation.rows[0].score == nil)
        #expect(presentation.myScore == nil && !presentation.myAnswerIsBlank)
    }

    @Test func readAloudShowsAnAnswerOnceScored() {
        let state = makeState(silent: false, answers: answers,
                              scores: [host.id: [10, 10, nil], ana.id: [5, 0, nil], bia.id: [nil, nil, nil],
                                       caio.id: [0, 5, nil]])
        let presentation = ScoringPresentation(state: state, viewer: ana.id)
        #expect(presentation.rows.map(\.isHidden) == [false, false, true, false])
        #expect(presentation.rows[0].answer == "Bear" && presentation.rows[0].score == 10)
    }

    @Test func readAloudShowsTheHostThePlayersItMayScoreFor() {
        // Bia is away: the host may score for her, so it sees her answer (and its snapshot includes it).
        let state = makeState(silent: false, answers: answers,
                              scores: [host.id: [10, nil, nil], ana.id: [5, nil, nil], bia.id: [nil, nil, nil],
                                       caio.id: [0, nil, nil]])
        let presentation = ScoringPresentation(state: state, viewer: host.id)
        #expect(presentation.rows.map(\.isHidden) == [false, true, false, false])
        #expect(presentation.rows[2].answer == "Bee")
        #expect(presentation.canHostScore.contains(bia.id))
    }

    @Test func silentModeShowsEveryAnswer() {
        let state = makeState(answers: answers, scores: [host.id: [10, nil, nil], ana.id: [5, nil, nil],
                                                         bia.id: [nil, nil, nil], caio.id: [0, nil, nil]])
        let presentation = ScoringPresentation(state: state, viewer: ana.id)
        #expect(!presentation.isReadAloud)
        #expect(presentation.rows.allSatisfy { !$0.isHidden })
        #expect(presentation.rows.map(\.answer) == ["Bear", "—", "Bee", "Bat"])
    }

    @Test func onlyTheHostGoesBackAndNotFromTheFirstCategory() {
        let second = makeState(category: 1, answers: answers, scores: allScored)
        #expect(ScoringPresentation(state: second, viewer: host.id).showsPreviousButton)
        #expect(!ScoringPresentation(state: second, viewer: ana.id).showsPreviousButton)
        let first = makeState(category: 0, completed: true, answers: answers, scores: allScored)
        #expect(!ScoringPresentation(state: first, viewer: host.id).showsPreviousButton)
    }

    @Test func lastCategoryLeadsToResults() {
        #expect(!ScoringPresentation(state: makeState(category: 1, completed: true, answers: answers,
                                                      scores: allScored), viewer: host.id).isLastCategory)
        #expect(ScoringPresentation(state: makeState(category: 2, completed: true, answers: answers,
                                                     scores: allScored), viewer: host.id).isLastCategory)
    }

    @Test func everyoneSeesEveryScore() {
        let state = makeState(completed: false, answers: answers,
                              scores: [host.id: [10, 10, nil], ana.id: [5, 0, nil], bia.id: [nil, nil, nil],
                                       caio.id: [0, 5, nil]])
        // Not just the viewer's: every row carries its current score (nil until picked), even before completion.
        #expect(ScoringPresentation(state: state, viewer: ana.id).rows.map(\.score) == [10, 0, nil, 5])
    }
}
