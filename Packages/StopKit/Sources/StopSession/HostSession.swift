import Foundation
import Observation
import StopCore
import StopNetworking

/// The authoritative game on the host phone: applies intents through `GameEngine`, drives ticks and presence,
/// broadcasts redacted snapshots and persists every change. Connection handling lives in `+Connections`.
@MainActor @Observable
public final class HostSession {
    /// Authoritative and unredacted.
    public private(set) var state: GameState
    /// The `GameClient` for the host's own UI.
    public let localClient: LocalGameClient

    let factory: any TransportFactory
    let store: any GameStore
    let clock: any Clock<Duration>
    let timing: SessionTiming
    @ObservationIgnored var rng: any RandomNumberGenerator & Sendable

    @ObservationIgnored var listener: (any Listener)?
    @ObservationIgnored var listenerFailed = false
    @ObservationIgnored var advertised: Advertisement?
    @ObservationIgnored var openConnections: [UUID: any Connection] = [:]
    @ObservationIgnored var connectionPlayer: [UUID: PlayerID] = [:]
    @ObservationIgnored var playerConnection: [PlayerID: any Connection] = [:]
    /// Started at each connected player's last message.
    @ObservationIgnored var lastSeen: [PlayerID: Stopwatch] = [:]
    @ObservationIgnored var intentLogs: [PlayerID: IntentLog] = [:]
    @ObservationIgnored var isShutDown = false

    @ObservationIgnored private var loops: [Task<Void, Never>] = []
    @ObservationIgnored private let storeQueue: StoreQueue
    @ObservationIgnored private var stateWriteQueued = false

    public init(state: GameState, factory: any TransportFactory, store: any GameStore, clock: any Clock<Duration>,
                timing: SessionTiming = .standard,
                rng: any RandomNumberGenerator & Sendable = SystemRandomNumberGenerator()) {
        // Restored games: nobody but the host is connected yet.
        var restored = state
        for player in state.players where player.id != state.hostID && player.presence == .present {
            _ = GameEngine.setPresence(.away, for: player.id, in: &restored)
        }
        self.state = restored
        self.factory = factory
        self.store = store
        self.clock = clock
        self.timing = timing
        self.rng = rng
        storeQueue = StoreQueue(store)
        localClient = LocalGameClient(hostID: state.hostID, queue: storeQueue, clock: clock, timing: timing)
        localClient.host = self
    }

    // MARK: Lifecycle

    /// Listener up, advertise, start heartbeat and tick loops, persist the game and `ActiveGameRef(.host)`.
    public func start() {
        guard !isShutDown, listener == nil else { return }
        startListener()
        startLoops()
        let ref = ActiveGameRef(gameID: state.gameID, role: .host, hostName: hostName)
        enqueueStore { await $0.saveActiveGame(ref) }
        persist()
        localClient.hostStateDidChange(from: nil)
    }

    /// Scene background: tell everyone, persist, stop the loops (so countdowns pause).
    public func suspend() {
        guard !isShutDown else { return }
        broadcast(.goingAway)
        stopLoops()
        localClient.flushDraft()
        persist()
    }

    /// Scene foreground: restart a failed listener and the loops, then resync everyone.
    public func resume() {
        guard !isShutDown else { return }
        if listener == nil || listenerFailed {
            listener?.stop()
            startListener()
        }
        lastSeen = lastSeen.mapValues { _ in Stopwatch(clock) }
        startLoops()
        broadcastSnapshots()
    }

    /// Stops everything and clears the persisted game, its reference and drafts. The listener and connections
    /// stay up 5 s more so clients receive the final snapshot.
    public func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        stopLoops()
        localClient.discardPendingDraft()
        let gameID = state.gameID
        enqueueStore { store in
            await store.saveHostGame(nil)
            await store.saveActiveGame(nil)
            await store.clearDrafts(gameID: gameID)
        }
        Task { [weak self, clock] in
            do { try await clock.sleep(for: .seconds(5)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.closeTransport()
        }
    }

    private func closeTransport() {
        listener?.stop()
        listener = nil
        for connection in openConnections.values { connection.close() }
    }

    // MARK: State changes

    /// Applies `intent` as `sender`; on change persists, broadcasts (skipping `except`) and updates the ad.
    func apply(_ intent: Intent, from sender: PlayerID, except: PlayerID? = nil) -> GameError? {
        guard !isShutDown else { return .gameClosed }
        var next = state
        do throws(GameError) {
            try GameEngine.apply(intent, from: sender, to: &next, using: &rng)
        } catch {
            return error
        }
        if next.version != state.version { commit(next, except: except) }
        return nil
    }

    /// Runs a non-intent change (tick, presence); commits it when `change` returns true.
    func mutate(_ change: (inout GameState) -> Bool) {
        guard !isShutDown else { return }
        var next = state
        if change(&next) { commit(next) }
    }

    func markAway(_ player: PlayerID) {
        mutate { GameEngine.setPresence(.away, for: player, in: &$0) }
    }

    private func commit(_ next: GameState, except: PlayerID? = nil) {
        let old = state
        state = next
        persist()
        broadcastSnapshots(except: except)
        updateAdvertisement()
        localClient.hostStateDidChange(from: old)
        if state.phase == .gameOver { shutdown() }
    }

    // MARK: Broadcast and advertisement

    func broadcastSnapshots(except: PlayerID? = nil) {
        for (player, connection) in playerConnection where player != except {
            send(.snapshot(state.redacted(for: player)), to: connection)
        }
    }

    func broadcast(_ body: WireMessage.Body) {
        for connection in playerConnection.values { send(body, to: connection) }
    }

    func send(_ body: WireMessage.Body, to connection: any Connection) {
        guard let data = try? WireMessage(body: body).encoded() else { return }
        connection.send(data)
    }

    private var hostName: String { state.player(state.hostID)?.name ?? "" }

    func advertisement() -> Advertisement {
        Advertisement(gameID: state.gameID, hostName: hostName, playerCount: state.activePlayers.count,
                      protocolVersion: currentProtocolVersion, joinable: state.phase == .lobby)
    }

    private func updateAdvertisement() {
        let ad = advertisement()
        guard let listener, ad != advertised else { return }
        advertised = ad
        listener.update(ad)
    }

    // MARK: Loops

    private func startLoops() {
        guard loops.isEmpty else { return }
        loops = [
            repeating(every: timing.heartbeat) { $0.heartbeat() },
            repeating(every: timing.tick) { session in session.mutate { GameEngine.tick(&$0) } },
        ]
    }

    private func stopLoops() {
        for loop in loops { loop.cancel() }
        loops = []
    }

    private func repeating(every interval: Duration,
                           _ body: @escaping @MainActor (HostSession) -> Void) -> Task<Void, Never> {
        Task { [weak self, clock] in
            while true {
                do { try await clock.sleep(for: interval) } catch { return }
                guard !Task.isCancelled, let self else { return }
                body(self)
            }
        }
    }

    /// Sends `.heartbeat` to everyone and marks players away once silent for `awayAfter`.
    private func heartbeat() {
        broadcast(.heartbeat)
        for player in Array(playerConnection.keys) where (lastSeen[player]?.elapsed ?? .zero) >= timing.awayAfter {
            markAway(player)
        }
    }

    // MARK: Persistence

    /// Store operations run one at a time, in order, so a final clear can't be overtaken by an earlier save.
    func enqueueStore(_ operation: @escaping @MainActor (any GameStore) async -> Void) {
        storeQueue.enqueue(operation)
    }

    /// Saves the latest state; changes arriving while a save is queued are coalesced into it.
    private func persist() {
        guard !isShutDown, !stateWriteQueued else { return }
        stateWriteQueued = true
        enqueueStore { [weak self] store in
            guard let self, !self.isShutDown else { return }
            self.stateWriteQueued = false
            await store.saveHostGame(self.state)
        }
    }
}

/// Recent intent IDs with the ack each got, so a retried intent gets the same reply and isn't applied twice.
struct IntentLog {
    static let capacity = 512
    private var acks: [UUID: GameError?] = [:]
    private var order: [UUID] = []

    /// The recorded ack (`.some(nil)` for success), or nil if `id` is unknown.
    mutating func ack(for id: UUID) -> GameError?? {
        guard let ack = acks[id] else { return nil }
        if let index = order.firstIndex(of: id) { order.append(order.remove(at: index)) }
        return .some(ack)
    }

    mutating func record(_ id: UUID, _ error: GameError?) {
        acks[id] = .some(error)
        order.append(id)
        if order.count > Self.capacity { acks[order.removeFirst()] = nil }
    }
}
