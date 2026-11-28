import Observation
import StopSession
import SwiftUI

/// The host's phone went quiet. While writing it's a banner at the top, so typing carries on; in every other
/// phase it dims the screen (the game can't move without the host). After `hostGoneAfter` it says the host may
/// be gone and offers to leave.
struct HostAwayOverlay: View {
    enum Presentation {
        case banner, fullScreen
    }

    /// The host's on-screen name, if the game is known yet.
    let hostName: String?
    let mayBeGone: Bool
    /// Local network access is off, so the host can't be reached until it's turned back on.
    let networkDenied: Bool
    let presentation: Presentation
    let onLeave: () -> Void

    @State private var confirmsLeaving = false

    private var copy: HostAwayCopy {
        HostAwayCopy(hostName: hostName, mayBeGone: mayBeGone, networkDenied: networkDenied,
                     whileWriting: presentation == .banner)
    }

    var body: some View {
        Group {
            switch presentation {
            case .banner:
                banner
            case .fullScreen:
                ZStack {
                    Theme.edge.opacity(0.5)
                        .ignoresSafeArea()
                        .accessibilityHidden(true)
                    card
                        .padding(Theme.Spacing.l)
                }
            }
        }
        .leaveConfirmation(isPresented: $confirmsLeaving, onLeave: onLeave)
        .onAppear(perform: announce)
        .onChange(of: mayBeGone) { announce() }
    }

    // MARK: Banner (writing)

    private var banner: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                icon(size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(copy.title).font(.system(.headline, design: .rounded, weight: .heavy))
                        .foregroundStyle(Theme.text)
                    Text(copy.message).font(Theme.Typography.caption).foregroundStyle(Theme.secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            actions(compact: true)
        }
        .padding(Theme.Spacing.m)
        .pieceCard()
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Stroke.depth)
        // Pinned over the answers, so it stops growing at the second accessibility size (like the header below).
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityIdentifier("hostAwayBanner")
    }

    // MARK: Full screen

    private var card: some View {
        VStack(spacing: Theme.Spacing.l) {
            VStack(spacing: Theme.Spacing.m) {
                icon(size: 44)
                Text(copy.title)
                    .font(Theme.Typography.headline)
                    .fontWeight(.heavy)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(copy.message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            actions(compact: false)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: 420)
        .pieceCard(depth: 6)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("hostAwayOverlay")
    }

    // MARK: Parts

    @ViewBuilder private func icon(size: CGFloat) -> some View {
        if size > 30 {
            StatusBadge(icon: copy.systemImage.map(StatusIcon.symbol) ?? .progress, size: 56)
        } else {
            Group {
                if let symbol = copy.systemImage {
                    Image(systemName: symbol)
                        .font(.system(size: size, weight: .bold))
                        .foregroundStyle(Theme.accent)
                } else {
                    ProgressView()
                        .tint(Theme.accent)
                }
            }
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func actions(compact: Bool) -> some View {
        if networkDenied || mayBeGone {
            let layout = compact ? AnyLayout(HStackLayout(spacing: Theme.Spacing.s))
                                 : AnyLayout(VStackLayout(spacing: Theme.Spacing.s))
            layout {
                if networkDenied { OpenSettingsButton(compact: compact) }
                if mayBeGone {
                    Button {
                        confirmsLeaving = true
                    } label: {
                        Text("Leave game")
                    }
                    .modifier(OverlayButtonStyle(compact: compact, prominent: !networkDenied))
                    .accessibilityHint(Text("Asks to confirm leaving the game."))
                    .accessibilityIdentifier("hostGoneLeaveButton")
                }
            }
        }
    }

    private func announce() {
        var text = String(localized: copy.title)
        if networkDenied || mayBeGone { text += ". " + String(localized: copy.message) }
        AccessibilityNotification.Announcement(text).post()
    }
}

/// What the host-away overlay and the rejoining screen say while the host can't be reached.
struct HostAwayCopy {
    /// A symbol, or nil for a spinner (still waiting).
    let systemImage: String?
    let title: LocalizedStringResource
    let message: LocalizedStringResource

    /// `whileWriting`: the message tells the player to keep typing. `rejoining`: the game is being resumed after
    /// a relaunch, so the plain wait says "Reconnecting to Ana's game…".
    init(hostName: String?, mayBeGone: Bool, networkDenied: Bool, whileWriting: Bool = false,
         rejoining: Bool = false) {
        let hostName = hostName.flatMap { $0.isEmpty ? nil : $0 }
        systemImage = networkDenied ? "wifi.exclamationmark" : mayBeGone ? "wifi.slash" : nil

        if networkDenied && rejoining {
            title = LocalizedStringResource("Allow Local Network access",
                                            comment: "Title when the app was denied Local Network access.")
        } else if mayBeGone {
            title = LocalizedStringResource(
                "The host may be gone",
                comment: "Title shown when the host's phone has been unreachable for about 2 minutes.")
        } else if rejoining {
            if let hostName {
                title = LocalizedStringResource(
                    "Reconnecting to \(hostName)’s game…",
                    comment: "Title while resuming an interrupted game after a relaunch. %@ is the host's name.")
            } else {
                title = LocalizedStringResource(
                    "Rejoining game…", comment: "Title while resuming an interrupted game whose host's name isn't known.")
            }
        } else if let hostName {
            title = LocalizedStringResource(
                "Waiting for \(hostName) to come back",
                comment: "Title while the host's phone is away (app in the background or out of range). %@ is the host's name.")
        } else {
            title = LocalizedStringResource(
                "Waiting for the host to come back",
                comment: "Title while the host's phone is away, before the host's name is known.")
        }

        if networkDenied {
            message = LocalizedStringResource(
                "Local Network access is off, so this phone can’t reach the game. Turn it on in Settings.",
                comment: "Explains that this app was denied Local Network access, so the game can't be reached.")
        } else if mayBeGone {
            message = LocalizedStringResource(
                "You can keep waiting, or leave the game. Your points so far stay in the standings.",
                comment: "What the player can do when the host's phone has been away for a long time.")
        } else if rejoining {
            message = LocalizedStringResource(
                "Keep the app open. You’ll be back in the game as soon as the host’s phone is nearby.",
                comment: "While resuming an interrupted game after a relaunch.")
        } else if whileWriting {
            message = LocalizedStringResource(
                "Keep writing. The round goes on when the host is back.",
                comment: "Host away during writing: typing continues.")
        } else {
            message = LocalizedStringResource(
                "The game picks up right where it left off.",
                comment: "Host away outside writing: nothing is lost.")
        }
    }
}

/// Shows the host-away overlay only once the host has been away for `grace` without a break, so the client's
/// own return from the background (a moment of `.away` before it reconnects) doesn't flash it.
/// `.mayBeGone` shows at once.
@MainActor @Observable
final class HostAwayGate {
    static let grace: Duration = .milliseconds(1500)

    private(set) var isShowing = false

    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private var pending: Task<Void, Never>?

    init(clock: any Clock<Duration> = ContinuousClock()) {
        self.clock = clock
    }

    func update(_ status: HostStatus) {
        switch status {
        case .mayBeGone:
            cancelPending()
            isShowing = true
        case .away:
            guard !isShowing, pending == nil else { return }
            pending = Task { [weak self, clock] in
                do { try await clock.sleep(for: Self.grace) } catch { return }
                self?.pending = nil
                self?.isShowing = true
            }
        case .connecting, .connected, .ended:
            cancelPending()
            isShowing = false
        }
    }

    private func cancelPending() {
        pending?.cancel()
        pending = nil
    }
}

extension View {
    /// The game menu's "Leave the game?" confirmation, for a guest (the host can't be away from itself).
    func leaveConfirmation(isPresented: Binding<Bool>, onLeave: @escaping () -> Void) -> some View {
        alert(Text("Leave the game?"), isPresented: isPresented) {
            Button("Leave", role: .destructive, action: onLeave)
                .accessibilityIdentifier("confirmLeaveButton")
        } message: {
            Text("Your points so far stay in the standings.")
        }
    }
}

/// Opens this app's page in Settings (to turn Local Network access back on).
struct OpenSettingsButton: View {
    var compact = false

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        } label: {
            Label("Open Settings", systemImage: "gearshape.fill")
        }
        .modifier(OverlayButtonStyle(compact: compact, prominent: true))
        .accessibilityIdentifier("openSettingsButton")
    }
}

/// Full-width app buttons on a card; small capsules in a banner.
private struct OverlayButtonStyle: ViewModifier {
    let compact: Bool
    let prominent: Bool

    func body(content: Content) -> some View {
        if compact {
            content.buttonStyle(CompactPieceButtonStyle(prominent: prominent))
        } else if prominent {
            content.buttonStyle(.primary)
        } else {
            content.buttonStyle(.secondary)
        }
    }
}

/// A small game-piece button for the host-away banner.
private struct CompactPieceButtonStyle: ButtonStyle {
    let prominent: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.reduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var minHeight: CGFloat = 40

    func makeBody(configuration: Configuration) -> some View {
        PieceButtonBody(configuration: configuration, fill: prominent ? Theme.accentFill : Theme.surface,
                        foreground: prominent ? Theme.onAccent : Theme.accent,
                        edge: prominent ? Theme.accentEdge : Theme.edge, minHeight: minHeight, isEnabled: isEnabled,
                        reduceMotion: reduceMotion, font: Theme.Typography.label, cornerRadius: 12)
    }
}

#Preview("Host away – full screen") {
    HostAwayOverlay(hostName: "Gui", mayBeGone: false, networkDenied: false, presentation: .fullScreen) {}
        .background(Theme.background)
}

#Preview("Host may be gone – full screen") {
    HostAwayOverlay(hostName: "Gui", mayBeGone: true, networkDenied: false, presentation: .fullScreen) {}
        .background(Theme.background)
}

#Preview("Host away – banner") {
    VStack {
        HostAwayOverlay(hostName: "Gui", mayBeGone: false, networkDenied: false, presentation: .banner) {}
        HostAwayOverlay(hostName: "Gui", mayBeGone: true, networkDenied: true, presentation: .banner) {}
        Spacer()
    }
    .background(Theme.background)
}
