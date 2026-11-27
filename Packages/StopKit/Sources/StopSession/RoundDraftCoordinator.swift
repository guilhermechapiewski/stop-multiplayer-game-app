import Foundation
import Observation
import StopCore

/// The local player's answers for the round in play, shared by `ClientSession` and `LocalGameClient`:
/// freezes them at STOP / give up (optimistically) and at the lock, submits them once per round when the host
/// still needs them, and persists drafts keyed by (game, round) with a debounce. A draft is only ever read
/// back for its own game and round.
@MainActor @Observable
final class RoundDraftCoordinator {
    /// Answers frozen at STOP / give up or at the lock, for the round in play; nil otherwise.
    private(set) var frozenAnswers: [String]?

    /// Sends `.submitAnswers(round:answers:)` for the local player.
    @ObservationIgnored var onSubmit: (_ round: Int, _ answers: [String]) -> Void = { _, _ in }

    private struct RoundKey: Equatable {
        var gameID: UUID
        var round: Int
    }

    @ObservationIgnored private let localPlayerID: PlayerID
    @ObservationIgnored private let queue: StoreQueue
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var state: GameState?
    /// The round `frozenAnswers` belongs to.
    @ObservationIgnored private var frozenKey: RoundKey?
    /// The round whose lock was already handled (answers frozen and submitted).
    @ObservationIgnored private var lockedKey: RoundKey?
    /// A STOP / give up was sent and not yet acked.
    @ObservationIgnored private var stopPending = false
    @ObservationIgnored private var latest: (key: RoundKey, answers: [String])?
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var isClosed = false

    init(localPlayerID: PlayerID, queue: StoreQueue, clock: any Clock<Duration>, debounce: Duration) {
        self.localPlayerID = localPlayerID
        self.queue = queue
        self.clock = clock
        self.debounce = debounce
    }

    private var currentKey: RoundKey? {
        guard let state, let round = state.currentRound else { return nil }
        return RoundKey(gameID: state.gameID, round: round.number)
    }

    // MARK: Intents

    /// Call before sending `intent`: STOP and give up freeze their answers at once.
    func willSend(_ intent: Intent) {
        switch intent {
        case .stop(let answers), .giveUp(let answers):
            guard let key = currentKey else { return }
            stopPending = true
            freeze(answers, key)
        default:
            break
        }
    }

    /// The host accepted the STOP / give up.
    func stopAccepted() {
        stopPending = false
    }

    /// A STOP or give up was rejected: unfreeze, unless the lock already froze the fields for this round or
    /// the host already holds my answers for it.
    func stopRejected() {
        stopPending = false
        guard let key = currentKey, lockedKey != key,
              state?.currentRound?.answers[localPlayerID] == nil else { return }
        frozenAnswers = nil
        frozenKey = nil
    }

    // MARK: Drafts

    func saveDraft(_ answers: [String]) {
        guard !isClosed, let key = currentKey else { return }
        latest = (key, answers)
        pendingSave?.cancel()
        let clock = clock, debounce = debounce
        pendingSave = Task { [weak self] in
            do { try await clock.sleep(for: debounce) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.pendingSave = nil
            self.write(key, answers)
        }
    }

    /// The draft for the round in play.
    func draft() async -> [String]? {
        guard let key = currentKey else { return nil }
        return await load(key)
    }

    /// Writes a pending debounced save now.
    func flush() {
        guard let pendingSave, let latest else { return }
        pendingSave.cancel()
        self.pendingSave = nil
        write(latest.key, latest.answers)
    }

    /// Stops all saving (the game ended or shut down); with `clearing`, deletes that game's drafts after any
    /// write already queued.
    func close(clearing gameID: UUID? = nil) {
        isClosed = true
        pendingSave?.cancel()
        pendingSave = nil
        latest = nil
        if let gameID { queue.enqueue { await $0.clearDrafts(gameID: gameID) } }
    }

    private func write(_ key: RoundKey, _ answers: [String]) {
        guard !isClosed else { return }
        queue.enqueue { await $0.saveDraft(answers, gameID: key.gameID, round: key.round) }
    }

    private func load(_ key: RoundKey) async -> [String]? {
        if let latest, latest.key == key { return latest.answers }
        return await queue.store.loadDraft(gameID: key.gameID, round: key.round)
    }

    // MARK: Round lock

    /// Feed every new state. At the lock (collecting or scoring) a participant without answers freezes the
    /// round's draft (or blanks) and submits it once; outside a round the fields unfreeze.
    func stateDidChange(_ state: GameState) {
        self.state = state
        guard let round = state.currentRound, let key = currentKey else { return unfreeze() }
        if frozenKey != key { unfreeze() }
        let mine = round.answers[localPlayerID]
        switch state.phase {
        case .writing:
            if let mine {
                if frozenAnswers == nil { freeze(mine, key) }
            } else if !stopPending {
                // Writing with no answers of mine (e.g. a host restored from before the lock): editable again.
                if lockedKey == key { lockedKey = nil }
                unfreeze()
            }
        case .collecting, .scoring:
            if let mine {
                if frozenAnswers == nil { freeze(mine, key) }
            } else if round.participants.contains(localPlayerID), lockedKey != key {
                lockedKey = key
                let count = state.settings.categories.count
                Task { await self.submitAtLock(key, categoryCount: count) }
            }
        case .lobby, .revealing, .countdown, .roundResults, .gameOver:
            unfreeze()
        }
    }

    private func submitAtLock(_ key: RoundKey, categoryCount count: Int) async {
        let optimistic = frozenKey == key ? frozenAnswers : nil
        let source: [String]
        if let optimistic { source = optimistic } else { source = await load(key) ?? [] }
        guard !isClosed, currentKey == key else { return }
        let answers = Array((source + Array(repeating: "", count: count)).prefix(count))
        freeze(answers, key)
        onSubmit(key.round, answers)
    }

    private func freeze(_ answers: [String], _ key: RoundKey) {
        frozenAnswers = answers
        frozenKey = key
    }

    private func unfreeze() {
        if frozenAnswers != nil { frozenAnswers = nil }
        frozenKey = nil
    }
}
