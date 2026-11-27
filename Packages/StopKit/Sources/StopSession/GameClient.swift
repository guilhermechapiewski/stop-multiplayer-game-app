import Foundation
import Observation
import StopCore

public enum HostStatus: Equatable, Sendable {
    case connecting, connected
    /// The host went quiet or said it was going away; the session moves on to `.mayBeGone` after `hostGoneAfter`.
    case away
    case mayBeGone
    case ended(EndReason)
}

public enum EndReason: Equatable, Sendable { case gameOver, leftGame, removed, versionMismatch, gameClosed }

@MainActor public protocol GameClient: AnyObject, Observable {
    var localPlayerID: PlayerID { get }
    var isHost: Bool { get }
    /// Redacted for the local player.
    var state: GameState? { get }
    var hostStatus: HostStatus { get }
    /// For banners.
    var presenceChanges: AsyncStream<PresenceChange> { get }
    /// Most recent rejected intent (UI may show/clear).
    var lastError: GameError? { get }
    /// Answers frozen when the round locked (for the writing screen); nil otherwise.
    var frozenAnswers: [String]? { get }
    func send(_ intent: Intent)
    /// Debounced persistence keyed by current game + round.
    func saveDraft(_ answers: [String])
    func draft() async -> [String]?
    /// Client: sends .leave then .bye and ends; host: endGame.
    func leave()
}
