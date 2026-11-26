import Foundation
import Testing
@testable import StopCore

@Test func blankDetection() { #expect(AnswerText.isBlank("  \n")); #expect(!AnswerText.isBlank(" a ")) }

@Test func settingsValidationTrimsDedupesAndRejectsEmpty() throws {
    let s = try GameSettings(categories: [" Animal ", "animal", "", "Fruta"], stopsRequired: 1, allowGiveUp: false).validated()
    #expect(s.categories == ["Animal", "Fruta"])
    #expect(throws: GameError.invalidSettings) { try GameSettings(categories: ["  "], stopsRequired: 1, allowGiveUp: false).validated() }
    #expect(throws: GameError.invalidSettings) { try GameSettings(categories: ["A"], stopsRequired: 0, allowGiveUp: false).validated() }
}

private let ana = Player(id: UUID(), name: "Ana", presence: .present)
private let bia = Player(id: UUID(), name: "Bia", presence: .away)
private let cai = Player(id: UUID(), name: "Cai", presence: .left)
private let dan = Player(id: UUID(), name: "Dan", presence: .removed)

private func makeState(stopsRequired: Int = 2, rounds: [Round] = []) -> GameState {
    GameState(gameID: UUID(), hostID: ana.id, version: 3, language: .ptBR,
              settings: GameSettings(categories: ["Nome", "Animal"], stopsRequired: stopsRequired, allowGiveUp: true),
              players: [ana, bia, cai, dan], phase: .writing, rounds: rounds, usedLetters: ["B"])
}

private func makeRound(_ n: Int, participants: [PlayerID], scores: [PlayerID: [Int?]] = [:]) -> Round {
    Round(number: n, letter: "B", participants: participants,
          stops: [StopRecord(playerID: ana.id, kind: .stop)],
          answers: [ana.id: ["Bia", "Boi"]], scores: scores, forceEnded: false)
}

@Test func gameStateRoundTripsThroughJSON() throws {
    var state = makeState(rounds: [makeRound(1, participants: [ana.id, bia.id], scores: [ana.id: [10, nil], bia.id: [nil, 5]])])
    state.phase = .scoring(categoryIndex: 1, completed: true)
    let decoded = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(state))
    #expect(decoded == state)
    #expect(decoded.rounds[0].scores[ana.id] == [10, nil])
}

@Test func intentAndErrorRoundTripThroughJSON() throws {
    let intent = Intent.setScore(round: 1, category: 0, points: 5, player: ana.id)
    #expect(try JSONDecoder().decode(Intent.self, from: JSONEncoder().encode(intent)) == intent)
    let error = GameError.staleRound
    #expect(try JSONDecoder().decode(GameError.self, from: JSONEncoder().encode(error)) == error)
}

@Test func defaultCategoriesExistForBothLanguages() {
    let pt = DefaultCategories.list(for: .ptBR), en = DefaultCategories.list(for: .en)
    #expect(pt.count >= 8 && en.count >= 8)
    #expect(Set(["Nome", "Animal", "Fruta", "CEP"]).isSubset(of: Set(pt)))
    #expect(Set(["Name", "Animal", "Fruit", "City"]).isSubset(of: Set(en)))
}

@Test func currentRoundIsLastRoundOrNil() {
    #expect(makeState().currentRound == nil)
    let state = makeState(rounds: [makeRound(1, participants: [ana.id]), makeRound(2, participants: [bia.id])])
    #expect(state.currentRound?.number == 2)
}

@Test func playerLookupById() {
    let state = makeState()
    #expect(state.player(bia.id)?.name == "Bia")
    #expect(state.player(UUID()) == nil)
}

@Test func activePlayersArePresentOrAway() {
    #expect(makeState().activePlayers.map(\.name) == ["Ana", "Bia"])
}

@Test func totalsSumNonNilScoresAcrossRounds() {
    let r1 = makeRound(1, participants: [ana.id, bia.id], scores: [ana.id: [10, nil], bia.id: [5, 5]])
    let r2 = makeRound(2, participants: [ana.id], scores: [ana.id: [5, 0]])
    let totals = makeState(rounds: [r1, r2]).totals
    #expect(totals[ana.id] == 15)
    #expect(totals[bia.id] == 10)
    #expect(totals[cai.id] == nil)
}

@Test func effectiveStopsRequiredIsCappedByRemainingParticipantsAndAtLeastOne() {
    // participants: ana (present), bia (away), cai (left), dan (removed) -> 2 remain
    let round = makeRound(1, participants: [ana.id, bia.id, cai.id, dan.id])
    #expect(makeState(stopsRequired: 3, rounds: [round]).effectiveStopsRequired == 2)
    #expect(makeState(stopsRequired: 1, rounds: [round]).effectiveStopsRequired == 1)
    let gone = makeRound(1, participants: [cai.id, dan.id])
    #expect(makeState(stopsRequired: 2, rounds: [gone]).effectiveStopsRequired == 1)
    #expect(makeState(stopsRequired: 2).effectiveStopsRequired == 1)  // no round yet
}
