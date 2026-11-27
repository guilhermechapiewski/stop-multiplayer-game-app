import Foundation
import Observation
import StopCore

/// The host's own `GameClient`: reads `HostSession.state` redacted for the host and applies intents in-process.
@MainActor @Observable
public final class LocalGameClient: GameClient {
    public let localPlayerID: PlayerID
    public var isHost: Bool { true }
    public var state: GameState? { host?.state.redacted(for: localPlayerID) }
    public var hostStatus: HostStatus { host?.state.phase == .gameOver ? .ended(.gameOver) : .connected }
    public let presenceChanges: AsyncStream<PresenceChange>
    public private(set) var lastError: GameError?
    public private(set) var frozenAnswers: [String]?

    @ObservationIgnored weak var host: HostSession?
    @ObservationIgnored private let presenceContinuation: AsyncStream<PresenceChange>.Continuation

    // Draft and lock handling: the minimum for the host; Task 11 lifts this into RoundDraftCoordinator.
    private struct Draft {
        var gameID: UUID
        var round: Int
        var answers: [String]
    }
    @ObservationIgnored private var latestDraft: Draft?
    @ObservationIgnored private var draftSave: Task<Void, Never>?
    @ObservationIgnored private var submittedRound: Int?

    init(hostID: PlayerID) {
        localPlayerID = hostID
        (presenceChanges, presenceContinuation) = AsyncStream.makeStream(of: PresenceChange.self)
    }

    public func send(_ intent: Intent) {
        guard let host else { return }
        let previousFrozen = frozenAnswers
        switch intent {
        case .stop(answers: let answers), .giveUp(answers: let answers): frozenAnswers = answers
        default: break
        }
        lastError = host.apply(intent, from: localPlayerID)
        if lastError != nil { frozenAnswers = previousFrozen }
    }

    public func saveDraft(_ answers: [String]) {
        guard let host, let round = host.state.currentRound?.number else { return }
        let gameID = host.state.gameID
        latestDraft = Draft(gameID: gameID, round: round, answers: answers)
        draftSave?.cancel()
        let clock = host.clock, delay = host.timing.draftDebounce
        draftSave = Task { [weak self] in
            do { try await clock.sleep(for: delay) } catch { return }
            self?.host?.enqueueStore { await $0.saveDraft(answers, gameID: gameID, round: round) }
        }
    }

    public func draft() async -> [String]? {
        guard let host, let round = host.state.currentRound?.number else { return nil }
        return await draft(gameID: host.state.gameID, round: round)
    }

    /// The host leaving ends the game.
    public func leave() { send(.endGame) }

    // MARK: Called by HostSession

    func hostStateDidChange(from old: GameState?) {
        guard let state = host?.state else { return }
        for change in PresenceDiff.changes(from: old, to: state) { presenceContinuation.yield(change) }
        syncRound(state)
    }

    func discardPendingDraft() {
        draftSave?.cancel()
        draftSave = nil
        latestDraft = nil
    }

    // MARK: Round lock

    /// On lock, submits the host's draft once per round; outside a round, unfreezes the fields.
    private func syncRound(_ state: GameState) {
        switch state.phase {
        case .collecting, .scoring:
            guard let round = state.currentRound, round.participants.contains(localPlayerID),
                  round.answers[localPlayerID] == nil, submittedRound != round.number else { return }
            submittedRound = round.number
            Task { await submitDraft(gameID: state.gameID, round: round.number) }
        case .writing:
            break
        case .lobby, .revealing, .countdown, .roundResults, .gameOver:
            if frozenAnswers != nil { frozenAnswers = nil }
        }
    }

    private func submitDraft(gameID: UUID, round: Int) async {
        let saved = await draft(gameID: gameID, round: round) ?? []
        guard let host, host.state.gameID == gameID else { return }
        let count = host.state.settings.categories.count
        let answers = Array((saved + Array(repeating: "", count: count)).prefix(count))
        frozenAnswers = answers
        // Errors (the round moved on meanwhile) are expected and not the user's doing.
        _ = host.apply(.submitAnswers(round: round, answers: answers), from: localPlayerID)
    }

    private func draft(gameID: UUID, round: Int) async -> [String]? {
        if let latestDraft, latestDraft.gameID == gameID, latestDraft.round == round { return latestDraft.answers }
        return await host?.store.loadDraft(gameID: gameID, round: round)
    }
}
