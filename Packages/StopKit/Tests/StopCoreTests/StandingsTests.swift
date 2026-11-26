import Foundation
import Testing
@testable import StopCore

private func player(_ name: String, _ presence: Presence = .present) -> Player {
    Player(id: UUID(), name: name, presence: presence)
}

@Test func competitionRankingSharesTies() {
    let a = player("A"), b = player("B"), c = player("C")
    let ranked = Standings.rank([a.id: 30, b.id: 30, c.id: 10], players: [a, b, c])
    #expect(ranked.map(\.rank) == [1, 1, 3])
    #expect(ranked.map(\.points) == [30, 30, 10])
}

@Test func tiesOrderedByJoinOrder() {
    let a = player("A"), b = player("B"), c = player("C")
    let ranked = Standings.rank([a.id: 5, b.id: 20, c.id: 5], players: [a, b, c])
    #expect(ranked.map(\.playerID) == [b.id, a.id, c.id])
}

@Test func includesLeftAndRemovedPlayers() {
    let a = player("A"), l = player("L", .left), r = player("R", .removed)
    let ranked = Standings.rank([a.id: 10, l.id: 20, r.id: 0], players: [a, l, r])
    #expect(ranked.map(\.playerID) == [l.id, a.id, r.id])
    #expect(ranked.first?.points == 20)
}

@Test func roundPointsSumsNonNilScores() {
    let a = player("A")
    let round = Round(number: 1, letter: "A", participants: [a.id], scores: [a.id: [10, nil, 5]])
    #expect(Standings.roundPoints(round) == [a.id: 15])
}

@Test func playersWithNoScoreGetZero() {
    let a = player("A"), b = player("B")
    let ranked = Standings.rank([a.id: 10], players: [a, b])
    #expect(ranked == [RankedEntry(playerID: a.id, rank: 1, points: 10),
                       RankedEntry(playerID: b.id, rank: 2, points: 0)])
}
