import Foundation
import StopCore
import StopNetworking

extension HostSession {
    func startListener() {
        let listener = factory.makeListener()
        self.listener = listener
        listenerFailed = false
        listenerFailedAt = nil
        let ad = advertisement()
        advertised = ad
        let events = listener.start(advertising: ad)
        Task { [weak self] in
            for await event in events {
                guard let self, self.listener === listener else { return }
                switch event {
                case .ready:
                    break
                case .permissionDenied:
                    isLocalNetworkDenied = true
                case .failed:
                    listenerFailed = true
                    listenerFailedAt = Stopwatch(clock)
                case .connection(let connection):
                    accept(connection)
                }
            }
        }
    }

    func restartListener() {
        listener?.stop()
        startListener()
    }

    /// From the heartbeat (so only in the foreground): restarts a failed listener once the backoff for the
    /// restarts so far has passed.
    func restartListenerIfDue() {
        guard listenerFailed, !isShutDown, let listenerFailedAt else { return }
        let backoff = timing.listenerRestartBackoff
        let delay = backoff.isEmpty ? .zero : backoff[min(listenerRestarts, backoff.count - 1)]
        guard listenerFailedAt.elapsed >= delay else { return }
        listenerRestarts += 1
        restartListener()
    }

    /// Browsing our own service type surfaces a local network denial; any results mean access works. A browser
    /// that ends is replaced on the next heartbeat.
    func startPermissionBrowser() {
        guard permissionBrowser == nil, !isShutDown else { return }
        let browser = factory.makeBrowser()
        permissionBrowser = browser
        let events = browser.start()
        Task { [weak self] in
            for await event in events {
                guard let self, self.permissionBrowser === browser else { return }
                switch event {
                case .results: if isLocalNetworkDenied { isLocalNetworkDenied = false }
                case .permissionDenied: if !isLocalNetworkDenied { isLocalNetworkDenied = true }
                case .failed: break
                }
            }
            if let self, self.permissionBrowser === browser { stopPermissionBrowser() }
        }
    }

    func stopPermissionBrowser() {
        permissionBrowser?.stop()
        permissionBrowser = nil
    }

    private func accept(_ connection: any Connection) {
        openConnections[connection.id] = connection
        connection.start()
        Task { [weak self] in
            for await event in connection.events {
                guard let self else { return }
                switch event {
                case .ready: break
                case .message(let data): receive(data, on: connection)
                case .closed: closed(connection)
                }
            }
        }
    }

    private func receive(_ data: Data, on connection: any Connection) {
        guard let message = try? WireMessage.decode(data) else { return }
        if case .hello(let playerID, let name, let gameID, _, let explicitRejoin) = message.body {
            hello(message.protocolVersion, playerID: playerID, name: name, gameID: gameID,
                  explicitRejoin: explicitRejoin, on: connection)
            return
        }
        guard let player = connectionPlayer[connection.id] else { return }
        switch message.body {
        case .goingAway:
            markAway(player)
        case .bye:
            // After a leave the engine keeps them `.left`; otherwise they're just gone for now.
            unmap(connection)
            connection.close()
            markAway(player)
        case .intent(let id, let intent):
            seen(player)
            handleIntent(intent, id: id, from: player, on: connection)
        case .heartbeat, .hello, .welcome, .rejected, .ack, .snapshot:
            seen(player)
        }
    }

    private func hello(_ protocolVersion: Int, playerID: PlayerID, name: String, gameID: UUID?,
                       explicitRejoin: Bool, on connection: any Connection) {
        guard protocolVersion == currentProtocolVersion else { return reject(connection, .versionMismatch) }
        if let gameID, gameID != state.gameID { return reject(connection, .wrongGame) }
        guard !isShutDown, playerID != state.hostID else { return reject(connection, .gameClosed) }
        if !explicitRejoin, state.player(playerID)?.presence == .removed {
            // A removed player's phone reconnecting on its own: show it the state (it ends with the "removed"
            // notice) without taking it back. Only choosing the game in the Join list rejoins.
            send(.welcome(state.redacted(for: playerID)), to: connection)
            connection.close()
            return
        }
        if let error = apply(.join(name: name), from: playerID, except: playerID) {
            if error == .gameClosed { send(.rejected(.gameClosed), to: connection) }
            connection.close()
            return
        }
        if let other = connectionPlayer[connection.id], other != playerID, unmap(connection) != nil {
            markAway(other)
        }
        if let previous = playerConnection[playerID], previous.id != connection.id {
            connectionPlayer[previous.id] = nil
            previous.close()
        }
        connectionPlayer[connection.id] = playerID
        playerConnection[playerID] = connection
        lastSeen[playerID] = Stopwatch(clock)
        // The join's broadcast skipped this player: the welcome carries the same state.
        send(.welcome(state.redacted(for: playerID)), to: connection)
    }

    private func reject(_ connection: any Connection, _ reason: RejectReason) {
        send(.rejected(reason), to: connection)
        connection.close()
    }

    private func handleIntent(_ intent: Intent, id: UUID, from player: PlayerID, on connection: any Connection) {
        var log = intentLogs[player] ?? IntentLog()
        let error: GameError?
        if let recorded = log.ack(for: id) {
            error = recorded
        } else {
            error = apply(intent, from: player)
            log.record(id, error)
        }
        intentLogs[player] = log
        send(.ack(id: id, error: error), to: connection)
    }

    /// Any message from a player resets their silence and brings them back if they were away.
    private func seen(_ player: PlayerID) {
        lastSeen[player] = Stopwatch(clock)
        guard state.player(player)?.presence == .away else { return }
        mutate { GameEngine.setPresence(.present, for: player, in: &$0) }
    }

    private func closed(_ connection: any Connection) {
        openConnections[connection.id] = nil
        guard let player = unmap(connection) else { return }
        markAway(player)
    }

    /// Forgets the connection's player mapping; returns the player if this was their current connection.
    @discardableResult
    private func unmap(_ connection: any Connection) -> PlayerID? {
        guard let player = connectionPlayer.removeValue(forKey: connection.id),
              playerConnection[player]?.id == connection.id else { return nil }
        playerConnection[player] = nil
        lastSeen[player] = nil
        return player
    }
}
