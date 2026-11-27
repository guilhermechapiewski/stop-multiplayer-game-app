import Foundation
import Observation
import StopCore
import SwiftUI

/// One "Ana left the app" style notice.
struct Banner: Equatable, Identifiable {
    enum Style: Equatable {
        case away, back, left, removed
    }

    let id = UUID()
    let playerID: PlayerID
    let text: String
    let style: Style

    init(change: PresenceChange, name: String) {
        playerID = change.playerID
        switch change.kind {
        case .wentAway:
            text = String(localized: "\(name) left the app",
                          comment: "Banner when another player puts the app in the background or drops off. %@ is the player's name.")
            style = .away
        case .returned:
            text = String(localized: "\(name) is back",
                          comment: "Banner when a player who was away reconnects. %@ is the player's name.")
            style = .back
        case .left:
            text = String(localized: "\(name) left the game",
                          comment: "Banner when a player taps Leave game. %@ is the player's name.")
            style = .left
        case .removed:
            text = String(localized: "\(name) was removed",
                          comment: "Banner when the host removes a player. %@ is the player's name.")
            style = .removed
        }
    }
}

/// Turns a session's presence changes into banners shown one at a time, `displayDuration` each, with at most
/// one waiting per player: a newer change replaces the older one (or the one showing). "Ana is back" right
/// after an unseen "Ana left the app" drops both.
@MainActor @Observable
final class BannerQueue {
    static let displayDuration: Duration = .seconds(3)

    private(set) var current: Banner?
    private var pending: [Banner] = []

    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private var consuming: Task<Void, Never>?
    @ObservationIgnored private var timer: Task<Void, Never>?

    init(clock: any Clock<Duration> = ContinuousClock()) {
        self.clock = clock
    }

    /// Banners waiting their turn.
    var pendingCount: Int { pending.count }

    /// Shows a banner for each change. `names` gives the on-screen names; players it leaves out are skipped.
    func consume(_ stream: AsyncStream<PresenceChange>, names: @escaping @MainActor () -> [PlayerID: String]) {
        consuming?.cancel()
        consuming = Task { [weak self] in
            for await change in stream {
                guard let self else { return }
                guard let name = names()[change.playerID] else { continue }
                self.enqueue(Banner(change: change, name: name))
            }
        }
    }

    /// Stops consuming and clears every banner.
    func stop() {
        consuming?.cancel()
        consuming = nil
        timer?.cancel()
        timer = nil
        pending = []
        current = nil
    }

    private func enqueue(_ banner: Banner) {
        if current?.playerID == banner.playerID {
            pending.insert(banner, at: 0)
            advance()
        } else if let index = pending.firstIndex(where: { $0.playerID == banner.playerID }) {
            // Away and back before anyone saw it: nothing to tell.
            if pending[index].style == .away, banner.style == .back {
                pending.remove(at: index)
            } else {
                pending[index] = banner
            }
        } else {
            pending.append(banner)
            if current == nil { advance() }
        }
    }

    /// Shows the next banner (or none) and starts its timer.
    private func advance() {
        timer?.cancel()
        guard !pending.isEmpty else {
            current = nil
            timer = nil
            return
        }
        current = pending.removeFirst()
        timer = Task { [weak self, clock] in
            do { try await clock.sleep(for: Self.displayDuration) } catch { return }
            self?.advance()
        }
    }
}

/// The banner at the top of the game screen. VoiceOver reads each one out.
struct PresenceBannerView: View {
    let banner: Banner

    var body: some View {
        Label {
            Text(verbatim: banner.text)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
        }
        .font(Theme.Typography.caption)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s + 2)
        .background(.regularMaterial, in: .capsule)
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.top, Theme.Spacing.s)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("presenceBanner")
        // The game screen gives each banner its own identity, so every one appears (and is read out) afresh.
        .onAppear { AccessibilityNotification.Announcement(banner.text).post() }
    }

    private var symbol: String {
        switch banner.style {
        case .away: "moon.zzz.fill"
        case .back: "hand.wave.fill"
        case .left: "figure.walk.departure"
        case .removed: "person.fill.xmark"
        }
    }

    private var tint: Color {
        switch banner.style {
        case .back: .green
        case .away, .left, .removed: .secondary
        }
    }
}

#Preview("Presence banners") {
    let id = UUID()
    VStack {
        PresenceBannerView(banner: Banner(change: PresenceChange(playerID: id, kind: .wentAway), name: "Ana"))
        PresenceBannerView(banner: Banner(change: PresenceChange(playerID: id, kind: .returned), name: "Ana"))
        PresenceBannerView(banner: Banner(change: PresenceChange(playerID: id, kind: .left), name: "Bia"))
        PresenceBannerView(banner: Banner(change: PresenceChange(playerID: id, kind: .removed), name: "Caio"))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.background)
}
