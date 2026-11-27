import Foundation
import Observation
import StopNetworking
import StopSession

/// Browses the local network for games while the Join screen is showing.
@MainActor @Observable
final class JoinModel {
    enum Availability: Equatable {
        case joinable
        /// Already started: new players can only join in the lobby.
        case inProgress
        /// Hosted with a different app version.
        case updateRequired
    }

    /// Games nearby: joinable ones first, then by host name.
    private(set) var games: [DiscoveredGame] = []
    /// The Local Network permission was refused, so nothing can be found.
    private(set) var permissionDenied = false

    @ObservationIgnored private let factory: any TransportFactory
    @ObservationIgnored private var browser: (any Browser)?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(factory: any TransportFactory) {
        self.factory = factory
    }

    static func availability(of game: DiscoveredGame) -> Availability {
        if game.advertisement.protocolVersion != currentProtocolVersion { return .updateRequired }
        return game.advertisement.joinable ? .joinable : .inProgress
    }

    func start() {
        guard browser == nil else { return }
        let browser = factory.makeBrowser()
        self.browser = browser
        let events = browser.start()
        task = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                self.handle(event)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        browser?.stop()
        browser = nil
    }

    private func handle(_ event: BrowserEvent) {
        switch event {
        case .results(let found):
            permissionDenied = false
            games = found.sorted { lhs, rhs in
                let lhsJoinable = Self.availability(of: lhs) == .joinable
                let rhsJoinable = Self.availability(of: rhs) == .joinable
                if lhsJoinable != rhsJoinable { return lhsJoinable }
                return lhs.advertisement.hostName.localizedStandardCompare(rhs.advertisement.hostName)
                    == .orderedAscending
            }
        case .permissionDenied:
            permissionDenied = true
            games = []
        case .failed:
            // The browser restarts itself; keep showing what we last saw.
            break
        }
    }
}
