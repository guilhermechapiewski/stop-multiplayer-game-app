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
    public var frozenAnswers: [String]? { drafts.frozenAnswers }

    @ObservationIgnored weak var host: HostSession?
    @ObservationIgnored private let presenceContinuation: AsyncStream<PresenceChange>.Continuation
    @ObservationIgnored private let drafts: RoundDraftCoordinator

    init(hostID: PlayerID, queue: StoreQueue, clock: any Clock<Duration>, timing: SessionTiming) {
        localPlayerID = hostID
        (presenceChanges, presenceContinuation) = AsyncStream.makeStream(of: PresenceChange.self)
        drafts = RoundDraftCoordinator(localPlayerID: hostID, queue: queue, clock: clock,
                                       debounce: timing.draftDebounce)
        drafts.onSubmit = { [weak self] round, answers in
            guard let self, let host else { return }
            lastError = host.apply(.submitAnswers(round: round, answers: answers), from: localPlayerID)
        }
    }

    public func send(_ intent: Intent) {
        guard let host else { return }
        drafts.willSend(intent)
        lastError = host.apply(intent, from: localPlayerID)
        switch intent {
        case .stop, .giveUp: if lastError != nil { drafts.stopRejected() } else { drafts.stopAccepted() }
        default: break
        }
    }

    public func saveDraft(_ answers: [String]) { drafts.saveDraft(answers) }

    public func draft() async -> [String]? { await drafts.draft() }

    /// The host leaving ends the game.
    public func leave() { send(.endGame) }

    // MARK: Called by HostSession

    func hostStateDidChange(from old: GameState?) {
        guard let state = host?.state else { return }
        for change in PresenceDiff.changes(from: old, to: state) { presenceContinuation.yield(change) }
        drafts.stateDidChange(state)
    }

    /// Stops draft saving; the host clears the game's drafts itself.
    func discardPendingDraft() { drafts.close() }

    /// Writes a pending debounced draft now (scene going to background).
    func flushDraft() { drafts.flush() }
}
