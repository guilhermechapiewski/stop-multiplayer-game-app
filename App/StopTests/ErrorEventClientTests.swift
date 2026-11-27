import Foundation
import Observation
import StopCore
import StopSession
import Testing
@testable import Stop

@MainActor
struct ErrorEventClientTests {
    /// Starts watching and waits until the watch has taken in the current error.
    func watching(_ base: any GameClient) async throws -> (ErrorEventClient, Task<Void, Never>) {
        let client = ErrorEventClient(base)
        let watch = Task { await client.watchErrors() }
        try await waitUntil { client.isWatching }
        return (client, watch)
    }

    @Test func anErrorFromTheHostBecomesAnEvent() async throws {
        let base = AnsweringClient(isHost: true)
        let (client, watch) = try await watching(base)
        defer { watch.cancel() }

        base.nextError = .notEnoughPlayers
        client.send(.startGame)

        try await waitUntil { client.lastEvent?.error == .notEnoughPlayers }
        #expect(base.sent == [.startGame])
    }

    @Test func theSameHostErrorTwiceMakesTwoEvents() async throws {
        let base = AnsweringClient(isHost: true)
        let (client, watch) = try await watching(base)
        defer { watch.cancel() }
        base.nextError = .notEnoughPlayers

        client.send(.startGame)
        try await waitUntil { client.lastEvent != nil }
        let first = try #require(client.lastEvent)
        client.send(.startGame)

        try await waitUntil { client.lastEvent != first }
        #expect(client.lastEvent?.error == .notEnoughPlayers)
    }

    @Test func aRemoteErrorBecomesAnEventWhenItArrives() async throws {
        let base = AnsweringClient(isHost: false)
        let (client, watch) = try await watching(base)
        defer { watch.cancel() }
        base.lastError = .notParticipant
        client.send(.giveUp(answers: []))
        // A remote ack arrives later and is reported when `lastError` changes; sending never re-reports it.
        try await waitUntil { client.lastEvent?.error == .notParticipant }
        let first = client.lastEvent
        client.send(.giveUp(answers: []))
        #expect(client.lastEvent == first)
    }

    @Test func anErrorFromBeforeTheWatchIsNotReported() async throws {
        let base = AnsweringClient(isHost: false)
        base.lastError = .gameClosed
        let (client, watch) = try await watching(base)
        defer { watch.cancel() }
        #expect(client.lastEvent == nil)
    }

    @Test func forwardsTheGame() {
        let base = AnsweringClient(isHost: true)
        let client = ErrorEventClient(base)
        #expect(client.localPlayerID == base.localPlayerID)
        #expect(client.isHost)
        base.hostStatus = .away
        #expect(client.hostStatus == .away)
        client.saveDraft(["Bear"])
        #expect(base.savedDrafts == [["Bear"]])
    }
}

/// A client whose host answers each intent at once with `nextError`, like `LocalGameClient` (when `isHost`).
@MainActor @Observable
final class AnsweringClient: GameClient {
    let localPlayerID = UUID()
    let isHost: Bool
    var state: GameState?
    var hostStatus: HostStatus = .connected
    let presenceChanges = AsyncStream<PresenceChange> { $0.finish() }
    var lastError: GameError?
    var frozenAnswers: [String]?
    var nextError: GameError?
    private(set) var sent: [Intent] = []
    private(set) var savedDrafts: [[String]] = []

    init(isHost: Bool) { self.isHost = isHost }

    func send(_ intent: Intent) {
        sent.append(intent)
        if isHost { lastError = nextError }
    }

    func saveDraft(_ answers: [String]) { savedDrafts.append(answers) }
    func draft() async -> [String]? { nil }
    func leave() {}
}
