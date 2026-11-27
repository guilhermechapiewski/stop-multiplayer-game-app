import Foundation
import StopCore
import StopNetworking

extension ClientSession {
    /// Reconnects while the session is running and the game hasn't ended.
    private var shouldReconnect: Bool { isStarted && !isStopped && !isEnded }

    /// Where to dial: where the browser sees the game now, else the last endpoint.
    private var reconnectEndpoint: EndpointRef? { browsedEndpoint ?? lastEndpoint }

    func connect(to endpoint: EndpointRef) {
        closeConnection()
        lastEndpoint = endpoint
        let connection = factory.connect(to: endpoint)
        self.connection = connection
        Task { [weak self] in
            for await event in connection.events {
                guard let self, self.connection?.id == connection.id else { return }
                switch event {
                case .ready: connectionReady()
                case .message(let data): receive(data)
                case .closed: connectionClosed(connection)
                }
            }
        }
        connection.start()
    }

    func closeConnection() {
        guard let connection else { return }
        self.connection = nil
        isWelcomed = false
        connection.close()
    }

    private func connectionClosed(_ closed: any Connection) {
        guard connection?.id == closed.id else { return }
        connection = nil
        isWelcomed = false
        guard shouldReconnect else { return }
        hostWentAway()
        startBrowsing()
        scheduleReconnect()
    }

    /// Waits `reconnectBackoff[min(attempt, count - 1)]`, then dials.
    func scheduleReconnect() {
        guard shouldReconnect, reconnectTask == nil, reconnectEndpoint != nil else { return }
        let backoff = timing.reconnectBackoff
        let delay = backoff.isEmpty ? .zero : backoff[min(reconnectAttempts, backoff.count - 1)]
        reconnectTask = Task { [weak self, clock] in
            do { try await clock.sleep(for: delay) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.reconnectTask = nil
            self.reconnectAttempts += 1
            self.reconnectNow()
        }
    }

    /// Dials now (if there's anywhere to dial); a failure schedules the next attempt.
    func reconnectNow() {
        cancelReconnect()
        guard shouldReconnect else { return }
        guard let endpoint = reconnectEndpoint else { return startBrowsing() }
        startBrowsing()
        connect(to: endpoint)
    }

    func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    // MARK: Browsing for the game ID

    /// Keeps `browsedEndpoint` pointing at the game while disconnected; the first sighting, when there was
    /// no endpoint yet (rejoin), dials at once.
    func startBrowsing() {
        guard browser == nil, shouldReconnect else { return }
        let browser = factory.makeBrowser()
        self.browser = browser
        let events = browser.start()
        Task { [weak self] in
            for await event in events {
                guard let self, self.browser === browser else { return }
                guard case .results(let games) = event else { continue }
                let endpoint = games.first { $0.advertisement.gameID == self.gameID }?.endpoint
                browsedEndpoint = endpoint
                if let endpoint, connection == nil, lastEndpoint == nil, shouldReconnect {
                    connect(to: endpoint)
                }
            }
        }
    }

    func stopBrowsing() {
        browser?.stop()
        browser = nil
        browsedEndpoint = nil
    }
}
