import Foundation
import Observation
import StopCore
import StopSession

/// Wraps the game screen's client to number its errors, so the toast shows again when the host turns down the
/// same thing twice in a row (`lastError` doesn't change then, so watching it alone misses the repeat).
///
/// The host's own client answers inside `send`, so a repeat is caught right there. A remote session's ack
/// arrives later and is reported when `lastError` changes.
@MainActor @Observable
final class ErrorEventClient: GameClient {
    struct Event: Equatable {
        let sequence: Int
        let error: GameError
    }

    let base: any GameClient
    /// The latest error reported, numbered so a repeat is a new value.
    private(set) var lastEvent: Event?
    /// `watchErrors()` has taken in the current error and is watching for changes (for tests).
    private(set) var isWatching = false
    @ObservationIgnored private var sequence = 0

    init(_ base: any GameClient) { self.base = base }

    var localPlayerID: PlayerID { base.localPlayerID }
    var isHost: Bool { base.isHost }
    var state: GameState? { base.state }
    var hostStatus: HostStatus { base.hostStatus }
    var presenceChanges: AsyncStream<PresenceChange> { base.presenceChanges }
    var lastError: GameError? { base.lastError }
    var frozenAnswers: [String]? { base.frozenAnswers }

    func send(_ intent: Intent) {
        let before = base.lastError
        base.send(intent)
        // Unchanged, so the watch won't see it: report the repeat here.
        if base.isHost, let after = base.lastError, after == before { report(after) }
    }

    func saveDraft(_ answers: [String]) { base.saveDraft(answers) }
    func draft() async -> [String]? { await base.draft() }
    func leave() { base.leave() }

    /// Reports every change of the base's `lastError` to an error, until cancelled. An error already there
    /// when the watch starts isn't reported.
    func watchErrors() async {
        defer { isWatching = false }
        for await error in Observations({ [base] in base.lastError }) {
            guard isWatching else {
                isWatching = true
                continue
            }
            if let error { report(error) }
        }
    }

    private func report(_ error: GameError) {
        sequence += 1
        lastEvent = Event(sequence: sequence, error: error)
    }
}
