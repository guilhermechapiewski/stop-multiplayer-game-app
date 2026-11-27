import Foundation
import Testing
import StopTestSupport
@testable import StopCore

private let settings = GameSettings(categories: ["Animal", "Fruta"], stopsRequired: 1, allowGiveUp: false)

private func lobby() throws -> (GameState, PlayerID) {
    let host = UUID()
    return (try GameEngine.newGame(gameID: UUID(), hostID: host, hostName: "Host", settings: settings, language: .en), host)
}

private func send(_ intent: Intent, _ id: PlayerID, _ state: inout GameState) throws {
    var rng = SeededRNG(seed: 7)
    try GameEngine.apply(intent, from: id, to: &state, using: &rng)
}

private func started() throws -> (GameState, PlayerID, PlayerID) {
    var (s, host) = try lobby()
    let b = UUID()
    try send(.join(name: "Bia"), b, &s)
    try send(.startGame, host, &s)
    return (s, host, b)
}

@Test func newGameHasHostPresentInLobby() throws {
    let (s, host) = try lobby()
    #expect(s.version == 0 && s.phase == .lobby && s.rounds.isEmpty)
    #expect(s.players == [Player(id: host, name: "Host", presence: .present)])
}

@Test func joinAddsPlayersByUUIDEvenWithDuplicateNames() throws {
    var (s, _) = try lobby()
    let a = UUID(), b = UUID()
    try send(.join(name: "Ana"), a, &s)
    try send(.join(name: " Ana "), b, &s)
    #expect(s.players.count == 3)
    #expect(Set(s.players.map(\.id)).count == 3)
    #expect(s.players.map(\.name) == ["Host", "Ana", "Ana"])
}

@Test func joinWithEmptyNameIsRejected() throws {
    var (s, _) = try lobby()
    #expect(throws: GameError.invalidSettings) { try send(.join(name: "  "), UUID(), &s) }
}

@Test func joinAfterStartIsRejectedForNewIDs() throws {
    var (s, _, _) = try started()
    let before = s
    #expect(throws: GameError.gameClosed) { try send(.join(name: "Late"), UUID(), &s) }
    #expect(s == before)
}

@Test func knownPlayerRejoinsAfterStart() throws {
    var (s, host, b) = try started()
    try send(.removePlayer(b), host, &s)
    #expect(s.player(b)?.presence == .removed)
    try send(.join(name: "Bia2"), b, &s)
    #expect(s.player(b)?.presence == .present)
    #expect(s.player(b)?.name == "Bia2")
    #expect(s.currentRound!.participants.contains(b))  // was a participant before removal
    var (s2, h2) = try lobby()
    let c = UUID()
    try send(.join(name: "C"), c, &s2)
    try send(.join(name: "D"), UUID(), &s2)
    try send(.leave, c, &s2)
    try send(.startGame, h2, &s2)
    try send(.join(name: "C"), c, &s2)
    #expect(s2.player(c)?.presence == .present)
    #expect(!s2.currentRound!.participants.contains(c))
}

@Test func nonHostCannotStartOrChangeSettings() throws {
    var (s, _) = try lobby()
    let b = UUID()
    try send(.join(name: "Bia"), b, &s)
    #expect(throws: GameError.notHost) { try send(.startGame, b, &s) }
    #expect(throws: GameError.notHost) { try send(.updateSettings(settings), b, &s) }
    #expect(throws: GameError.notHost) { try send(.removePlayer(b), b, &s) }
}

@Test func unknownSenderIsRejected() throws {
    var (s, _) = try lobby()
    #expect(throws: GameError.unknownPlayer) { try send(.leave, UUID(), &s) }
    #expect(throws: GameError.unknownPlayer) { try send(.startGame, UUID(), &s) }
}

@Test func startRequiresTwoPresentPlayers() throws {
    var (s, host) = try lobby()
    #expect(throws: GameError.notEnoughPlayers) { try send(.startGame, host, &s) }
    let b = UUID()
    try send(.join(name: "Bia"), b, &s)
    try send(.leave, b, &s)
    #expect(throws: GameError.notEnoughPlayers) { try send(.startGame, host, &s) }
}

@Test func startCreatesRoundOneWithLetterAndRevealPhase() throws {
    let (s, host, b) = try started()
    #expect(s.phase == .revealing(ticksRemaining: 2))
    #expect(s.usedLetters.count == 1)
    #expect(s.currentRound?.number == 1)
    #expect(s.currentRound?.letter == s.usedLetters[0])
    #expect(s.currentRound?.participants == [host, b])
}

@Test func categoriesCannotChangeAfterStart() throws {
    var (s, host, _) = try started()
    #expect(throws: GameError.wrongPhase) { try send(.updateSettings(settings), host, &s) }
}

@Test func updateSettingsValidatesInLobby() throws {
    var (s, host) = try lobby()
    try send(.updateSettings(GameSettings(categories: [" Cor ", "cor", "Nome"], stopsRequired: 2, allowGiveUp: true)), host, &s)
    #expect(s.settings.categories == ["Cor", "Nome"])
    #expect(throws: GameError.invalidSettings) {
        try send(.updateSettings(GameSettings(categories: [], stopsRequired: 1, allowGiveUp: false)), host, &s)
    }
}

@Test func roundSettingsEditableInLobbyAndResultsOnly() throws {
    var (s, host, _) = try started()
    #expect(throws: GameError.wrongPhase) { try send(.updateRoundSettings(stopsRequired: 2, allowGiveUp: true), host, &s) }
    s.phase = .roundResults
    try send(.updateRoundSettings(stopsRequired: 2, allowGiveUp: true), host, &s)
    #expect(s.settings.stopsRequired == 2 && s.settings.allowGiveUp)
    #expect(throws: GameError.invalidSettings) { try send(.updateRoundSettings(stopsRequired: 0, allowGiveUp: true), host, &s) }
    var (l, h) = try lobby()
    try send(.updateRoundSettings(stopsRequired: 3, allowGiveUp: true), h, &l)
    #expect(l.settings.stopsRequired == 3)
}

@Test func failedIntentLeavesStateUnchanged() throws {
    var (s, host) = try lobby()
    let before = s
    #expect(throws: GameError.notEnoughPlayers) { try send(.startGame, host, &s) }
    #expect(s == before)
    #expect(throws: GameError.wrongPhase) { try send(.nextRound, host, &s) }
    #expect(s == before)
}

@Test func versionIncrementsOncePerChange() throws {
    var (s, host) = try lobby()
    let b = UUID()
    try send(.join(name: "Bia"), b, &s)
    #expect(s.version == 1)
    try send(.join(name: "Bia"), b, &s)  // idempotent
    #expect(s.version == 1)
    try send(.updateRoundSettings(stopsRequired: 2, allowGiveUp: false), host, &s)
    #expect(s.version == 2)
    try send(.startGame, host, &s)
    #expect(s.version == 3)
    try send(.leave, b, &s)
    #expect(s.version == 4)
}

@Test func hostCannotLeave() throws {
    var (s, host) = try lobby()
    #expect(throws: GameError.notHost) { try send(.leave, host, &s) }
    #expect(throws: GameError.notHost) { try send(.removePlayer(host), host, &s) }
    #expect(s.player(host)?.presence == .present)
}

@Test func leaveAfterRemovalIsNoOp() throws {
    var (s, host, b) = try started()
    try send(.removePlayer(b), host, &s)
    let before = s
    try send(.leave, b, &s)
    #expect(s == before)
    #expect(s.player(b)?.presence == .removed)
}
