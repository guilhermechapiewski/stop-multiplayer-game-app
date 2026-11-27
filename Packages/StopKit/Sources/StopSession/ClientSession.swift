import Foundation
import Observation
import StopCore
import StopNetworking

/// A joined player's `GameClient`: mirrors the host's snapshots, queues intents until the host acks them
/// (resending after every reconnect), watches the host's liveness and keeps the local answers safe.
/// Reconnection lives in `+Reconnect`.
@MainActor @Observable
public final class ClientSession: GameClient {
    public enum Target: Sendable {
        case discovered(DiscoveredGame)
        /// Browses until a game with this ID appears.
        case rejoin(gameID: UUID)
    }

    public var localPlayerID: PlayerID { profile.playerID }
    public var isHost: Bool { false }
    public private(set) var state: GameState?
    public internal(set) var hostStatus: HostStatus = .connecting
    public let presenceChanges: AsyncStream<PresenceChange>
    public private(set) var lastError: GameError?
    /// Set at STOP / give up (optimistic) or on receiving the lock.
    public var frozenAnswers: [String]? { drafts.frozenAnswers }

    let profile: Profile
    let factory: any TransportFactory
    let clock: any Clock<Duration>
    let timing: SessionTiming
    @ObservationIgnored let storeQueue: StoreQueue
    @ObservationIgnored let drafts: RoundDraftCoordinator
    @ObservationIgnored private let presenceContinuation: AsyncStream<PresenceChange>.Continuation

    @ObservationIgnored let gameID: UUID
    /// The endpoint of the last connection attempt.
    @ObservationIgnored var lastEndpoint: EndpointRef?
    /// Where the browser currently sees our game, while browsing.
    @ObservationIgnored var browsedEndpoint: EndpointRef?
    @ObservationIgnored var connection: (any Connection)?
    @ObservationIgnored var isWelcomed = false
    /// Connection attempts since the last welcome; picks the backoff delay.
    @ObservationIgnored var reconnectAttempts = 0
    @ObservationIgnored var reconnectTask: Task<Void, Never>?
    @ObservationIgnored var browser: (any Browser)?
    @ObservationIgnored var isStarted = false
    @ObservationIgnored var isStopped = false

    private struct PendingIntent {
        let id: UUID
        let intent: Intent
    }
    @ObservationIgnored private var pending: [PendingIntent] = []
    @ObservationIgnored private var leaveID: UUID?
    @ObservationIgnored private var leaveTimeout: Task<Void, Never>?
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var lastHeard: Stopwatch
    /// Started when the current connection was dialed.
    @ObservationIgnored var dialed: Stopwatch
    @ObservationIgnored private var awaySince: Stopwatch?

    public init(profile: Profile, target: Target, factory: any TransportFactory, store: any GameStore,
                clock: any Clock<Duration>, timing: SessionTiming = .standard) {
        self.profile = profile
        self.factory = factory
        self.clock = clock
        self.timing = timing
        storeQueue = StoreQueue(store)
        drafts = RoundDraftCoordinator(localPlayerID: profile.playerID, queue: storeQueue, clock: clock,
                                       debounce: timing.draftDebounce)
        (presenceChanges, presenceContinuation) = AsyncStream.makeStream(of: PresenceChange.self)
        lastHeard = Stopwatch(clock)
        dialed = Stopwatch(clock)
        switch target {
        case .discovered(let game):
            gameID = game.advertisement.gameID
            lastEndpoint = game.endpoint
        case .rejoin(let id):
            gameID = id
        }
        drafts.onSubmit = { [weak self] round, answers in
            self?.enqueue(.submitAnswers(round: round, answers: answers))
        }
    }

    var isEnded: Bool {
        if case .ended = hostStatus { true } else { false }
    }

    /// For tests: intents not yet acked.
    var pendingIntentCount: Int { pending.count }

    // MARK: Lifecycle

    /// Connects to the target (browsing for it first when rejoining) and starts heartbeats.
    public func start() {
        guard !isEnded else { return }
        isStopped = false
        isStarted = true
        startWatchdog()
        guard connection == nil else { return }
        if let lastEndpoint {
            connect(to: lastEndpoint)
        } else {
            startBrowsing()
        }
    }

    /// Scene background: tell the host, stop heartbeats, write the pending draft.
    public func suspend() {
        guard !isEnded else { return }
        if isWelcomed { transmit(.goingAway) }
        stopWatchdog()
        drafts.flush()
    }

    /// Scene foreground: heartbeats again, and reconnect at once if not connected.
    public func resume() {
        guard !isEnded, isStarted else { return }
        lastHeard = Stopwatch(clock)
        startWatchdog()
        guard !isWelcomed else { return }
        reconnectAttempts = 0
        reconnectNow()
    }

    /// Tears everything down (the game stays persisted for a later rejoin).
    public func stop() {
        isStopped = true
        isStarted = false
        stopWatchdog()
        cancelReconnect()
        stopBrowsing()
        drafts.flush()
        closeConnection()
    }

    /// Gives up on the game without telling the host (e.g. the player cancels a rejoin): stops, then forgets
    /// the game and its drafts, queued after any draft write still pending so none is left behind.
    public func abandon() {
        stop()
        end(.leftGame)
    }

    // MARK: GameClient

    public func send(_ intent: Intent) {
        guard !isEnded else { return }
        drafts.willSend(intent)
        enqueue(intent)
    }

    public func saveDraft(_ answers: [String]) { drafts.saveDraft(answers) }

    public func draft() async -> [String]? { await drafts.draft() }

    /// Sends `.leave`, waits up to 1 s for its ack, then says `.bye` and ends.
    public func leave() {
        guard !isEnded, leaveID == nil else { return }
        leaveID = enqueue(.leave)
        leaveTimeout = Task { [weak self, clock] in
            do { try await clock.sleep(for: .seconds(1)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.finishLeaving()
        }
    }

    private func finishLeaving() {
        guard !isEnded else { return }
        if isWelcomed { transmit(.bye) }
        end(.leftGame)
    }

    // MARK: Intents

    @discardableResult
    private func enqueue(_ intent: Intent) -> UUID {
        let item = PendingIntent(id: UUID(), intent: intent)
        pending.append(item)
        if isWelcomed { transmit(.intent(id: item.id, intent)) }
        return item.id
    }

    private func acked(_ id: UUID, error: GameError?) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        let item = pending.remove(at: index)
        if let error {
            lastError = error
            switch item.intent {
            case .stop, .giveUp: drafts.stopRejected()
            default: break
            }
        }
        if id == leaveID { finishLeaving() }
    }

    // MARK: Messages

    func transmit(_ body: WireMessage.Body) {
        guard let connection, let data = try? WireMessage(body: body).encoded() else { return }
        connection.send(data)
    }

    func connectionReady() {
        transmit(.hello(playerID: profile.playerID, name: profile.name, gameID: gameID, lastVersion: state?.version))
    }

    func receive(_ data: Data) {
        guard let message = try? WireMessage.decode(data) else { return }
        if message.body == .goingAway {
            hostWentAway()
            return
        }
        heard()
        switch message.body {
        case .welcome(let welcome):
            isWelcomed = true
            reconnectAttempts = 0
            cancelReconnect()
            stopBrowsing()
            for item in pending { transmit(.intent(id: item.id, item.intent)) }
            if !isEnded { hostStatus = .connected }
            // The welcome is authoritative even if older than what we saw (the host may have restored an
            // earlier save).
            apply(welcome)
            guard !isEnded else { return }
            let ref = ActiveGameRef(gameID: welcome.gameID, role: .client,
                                    hostName: welcome.player(welcome.hostID)?.name ?? "")
            storeQueue.enqueue { await $0.saveActiveGame(ref) }
        case .rejected(let reason):
            switch reason {
            case .versionMismatch: end(.versionMismatch)
            case .gameClosed, .wrongGame: end(.gameClosed)
            }
        case .snapshot(let snapshot):
            guard isWelcomed else { return }
            if let state, snapshot.gameID == state.gameID, snapshot.version <= state.version { return }
            apply(snapshot)
        case .ack(let id, let error):
            acked(id, error: error)
        case .heartbeat, .hello, .intent, .goingAway, .bye:
            break
        }
    }

    private func apply(_ next: GameState) {
        let old = state
        state = next
        for change in PresenceDiff.changes(from: old, to: next) where change.playerID != localPlayerID {
            presenceContinuation.yield(change)
        }
        if next.player(localPlayerID)?.presence == .removed {
            end(.removed)
        } else if next.phase == .gameOver {
            end(.gameOver)
        } else {
            drafts.stateDidChange(next)
        }
    }

    // MARK: Host liveness

    private func heard() {
        lastHeard = Stopwatch(clock)
        awaySince = nil
        if isWelcomed, !isEnded, hostStatus != .connected { hostStatus = .connected }
    }

    /// The host went quiet, said it's going away, or the connection dropped.
    func hostWentAway() {
        guard !isEnded else { return }
        switch hostStatus {
        case .connected:
            hostStatus = .away
            awaySince = Stopwatch(clock)
        case .connecting, .away, .mayBeGone, .ended:
            break
        }
    }

    private func startWatchdog() {
        guard watchdog == nil else { return }
        watchdog = Task { [weak self, clock, timing] in
            while true {
                do { try await clock.sleep(for: timing.heartbeat) } catch { return }
                guard !Task.isCancelled, let self else { return }
                self.watch()
            }
        }
    }

    private func stopWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }

    /// Every heartbeat interval: send a heartbeat, update the host's status from how long it's been quiet, and
    /// recycle a connection that has gone silent (half-open) or never got a welcome.
    private func watch() {
        guard !isEnded else { return stopWatchdog() }
        if isWelcomed {
            transmit(.heartbeat)
            let quiet = lastHeard.elapsed
            if quiet >= timing.awayAfter { hostWentAway() }
            if quiet >= timing.reconnectAfterSilence { recycleConnection() }
        } else if connection != nil, dialed.elapsed >= timing.reconnectAfterSilence {
            recycleConnection()
        }
        if hostStatus == .away, let awaySince, awaySince.elapsed >= timing.hostGoneAfter {
            hostStatus = .mayBeGone
        }
    }

    // MARK: Ending

    func end(_ reason: EndReason) {
        guard !isEnded else { return }
        hostStatus = .ended(reason)
        stopWatchdog()
        cancelReconnect()
        stopBrowsing()
        leaveTimeout?.cancel()
        closeConnection()
        pending = []
        drafts.close(clearing: gameID)
        storeQueue.enqueue { await $0.saveActiveGame(nil) }
    }
}
