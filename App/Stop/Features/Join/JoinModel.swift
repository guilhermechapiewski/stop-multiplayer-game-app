import Foundation
import Observation
import StopNetworking
import StopSession

/// Browses the local network for games while the Join screen is showing. A browser that fails or finishes
/// is replaced after `restartDelay`; one that finished because Local Network access was refused is retried
/// when the app comes back to the foreground (the player may have just allowed it in Settings).
@MainActor @Observable
final class JoinModel {
    enum Availability: Equatable {
        case joinable
        /// Already started: new players can only join in the lobby.
        case inProgress
        /// Hosted with a different app version.
        case updateRequired
    }

    /// How long to wait before replacing a browser that failed or finished.
    static let restartDelay: Duration = .seconds(1)

    /// Games nearby: joinable ones first, then by host name.
    private(set) var games: [DiscoveredGame] = []
    /// The Local Network permission was refused, so nothing can be found.
    private(set) var permissionDenied = false

    /// On-screen host names by game ID, with a suffix when two hosts share a name.
    private var hostNames: [DiscoveredGame.ID: String] = [:]

    @ObservationIgnored private let factory: any TransportFactory
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var browser: (any Browser)?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(factory: any TransportFactory, clock: any Clock<Duration> = ContinuousClock()) {
        self.factory = factory
        self.clock = clock
    }

    static func availability(of game: DiscoveredGame) -> Availability {
        if game.advertisement.protocolVersion != currentProtocolVersion { return .updateRequired }
        return game.advertisement.joinable ? .joinable : .inProgress
    }

    /// The host's name as shown in the list ("Ana", "Ana 2").
    func hostName(of game: DiscoveredGame) -> String {
        hostNames[game.id] ?? game.advertisement.hostName
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startBrowser()
    }

    func stop() {
        isRunning = false
        stopBrowser()
    }

    /// The app is in the foreground again: if access was refused, try again now.
    func sceneBecameActive() {
        guard isRunning, permissionDenied else { return }
        startBrowser()
    }

    // MARK: Browsing

    private func startBrowser() {
        stopBrowser()
        let browser = factory.makeBrowser()
        self.browser = browser
        let events = browser.start()
        task = Task { [weak self] in
            for await event in events {
                guard let self, !Task.isCancelled else { return }
                if !self.handle(event) { break }
            }
            guard !Task.isCancelled else { return }
            await self?.browserEnded()
        }
    }

    private func stopBrowser() {
        task?.cancel()
        task = nil
        browser?.stop()
        browser = nil
    }

    /// The browser failed or finished: replace it after a pause, unless access was refused (then wait for
    /// `sceneBecameActive`).
    private func browserEnded() async {
        browser?.stop()
        browser = nil
        guard isRunning, !permissionDenied else { return }
        do { try await clock.sleep(for: Self.restartDelay) } catch { return }
        guard isRunning, browser == nil, !Task.isCancelled else { return }
        startBrowser()
    }

    /// Applies an event; false means this browser is done.
    private func handle(_ event: BrowserEvent) -> Bool {
        switch event {
        case .results(let found):
            permissionDenied = false
            // Hosts with the same name get "Ana 2", "Ana 3" by game ID, so the suffix doesn't jump around.
            let byID = found.sorted { $0.advertisement.gameID.uuidString < $1.advertisement.gameID.uuidString }
            let names = PlayerNameFormatter.disambiguated(byID.map(\.advertisement.hostName))
            hostNames = Dictionary(uniqueKeysWithValues: zip(byID.map(\.id), names))
            games = found.sorted { lhs, rhs in
                let lhsJoinable = Self.availability(of: lhs) == .joinable
                let rhsJoinable = Self.availability(of: rhs) == .joinable
                if lhsJoinable != rhsJoinable { return lhsJoinable }
                let order = hostName(of: lhs).localizedStandardCompare(hostName(of: rhs))
                if order != .orderedSame { return order == .orderedAscending }
                return lhs.id < rhs.id
            }
            return true
        case .permissionDenied:
            permissionDenied = true
            games = []
            hostNames = [:]
            return true
        case .failed:
            return false
        }
    }
}
