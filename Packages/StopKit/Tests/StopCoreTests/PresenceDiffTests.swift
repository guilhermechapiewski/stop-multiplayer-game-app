import Foundation
import Testing
@testable import StopCore

private let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()

private func state(gameID: UUID, _ presences: [(PlayerID, Presence)]) -> GameState {
    GameState(gameID: gameID, hostID: a, version: 1, language: .en,
              settings: GameSettings(categories: ["Animal"], stopsRequired: 1, allowGiveUp: false),
              players: presences.map { Player(id: $0.0, name: "P", presence: $0.1) },
              phase: .lobby, rounds: [], usedLetters: [])
}

@Test func diffReportsAwayReturnedLeftRemoved() {
    let game = UUID()
    let old = state(gameID: game, [(a, .present), (b, .present), (c, .away), (d, .present), (e, .away)])
    let new = state(gameID: game, [(a, .present), (b, .away), (c, .present), (d, .left), (e, .removed)])
    #expect(PresenceDiff.changes(from: old, to: new) == [
        PresenceChange(playerID: b, kind: .wentAway),
        PresenceChange(playerID: c, kind: .returned),
        PresenceChange(playerID: d, kind: .left),
        PresenceChange(playerID: e, kind: .removed),
    ])
}

@Test func diffReportsRejoinAsReturnedAndIgnoresNewPlayers() {
    let game = UUID()
    let old = state(gameID: game, [(a, .present), (b, .left), (c, .removed)])
    let new = state(gameID: game, [(a, .present), (b, .present), (c, .present), (d, .present)])
    #expect(PresenceDiff.changes(from: old, to: new) == [
        PresenceChange(playerID: b, kind: .returned),
        PresenceChange(playerID: c, kind: .returned),
    ])
}

@Test func diffEmptyForNewGame() {
    let new = state(gameID: UUID(), [(a, .present), (b, .away), (c, .left)])
    #expect(PresenceDiff.changes(from: nil, to: new).isEmpty)
    let other = state(gameID: UUID(), [(a, .present), (b, .present), (c, .present)])
    #expect(PresenceDiff.changes(from: other, to: new).isEmpty)
    #expect(PresenceDiff.changes(from: new, to: new).isEmpty)
}
