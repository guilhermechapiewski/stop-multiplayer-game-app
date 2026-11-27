import Foundation
import StopCore
import StopNetworking

extension HostSession {
    func startListener() {
        let listener = factory.makeListener()
        self.listener = listener
        listenerFailed = false
        let ad = advertisement()
        advertised = ad
        let events = listener.start(advertising: ad)
        Task { [weak self] in
            for await event in events {
                guard let self else { return }
                switch event {
                case .ready: break
                case .failed: listenerFailed = true
                case .connection(let connection): accept(connection)
                }
            }
        }
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
        if case .hello(let playerID, let name, let gameID, _) = message.body {
            hello(message.protocolVersion, playerID: playerID, name: name, gameID: gameID, on: connection)
            return
        }
        guard let player = connectionPlayer[connection.id] else { return }
        switch message.body {
        case .goingAway:
            markAway(player)
        case .bye:
            unmap(connection)
            connection.close()
        case .intent(let id, let intent):
            seen(player)
            handleIntent(intent, id: id, from: player, on: connection)
        case .heartbeat, .hello, .welcome, .rejected, .ack, .snapshot:
            seen(player)
        }
    }

    private func hello(_ protocolVersion: Int, playerID: PlayerID, name: String, gameID: UUID?,
                       on connection: any Connection) {
        guard protocolVersion == currentProtocolVersion else { return reject(connection, .versionMismatch) }
        if let gameID, gameID != state.gameID { return reject(connection, .wrongGame) }
        guard !isShutDown, playerID != state.hostID else { return reject(connection, .gameClosed) }
        if let error = apply(.join(name: name), from: playerID, except: playerID) {
            if error == .gameClosed { send(.rejected(.gameClosed), to: connection) }
            connection.close()
            return
        }
        if let previous = playerConnection[playerID], previous.id != connection.id {
            connectionPlayer[previous.id] = nil
            previous.close()
        }
        connectionPlayer[connection.id] = playerID
        playerConnection[playerID] = connection
        silence[playerID] = .zero
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
        silence[player] = .zero
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
        silence[player] = nil
        return player
    }
}
