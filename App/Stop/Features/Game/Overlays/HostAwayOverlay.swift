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

    /// Whether `status` calls for this overlay.
    static func shows(for status: HostStatus) -> Bool {
        status == .away || status == .mayBeGone
    }

    var body: some View {
        switch presentation {
        case .banner:
            banner
        case .fullScreen:
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                card
                    .padding(Theme.Spacing.l)
            }
        }
    }

    // MARK: Banner (writing)

    private var banner: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                icon(size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    title.font(.system(.headline, design: .rounded, weight: .bold))
                    message.font(Theme.Typography.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            actions(compact: true)
        }
        .padding(Theme.Spacing.m)
        .background(.regularMaterial, in: .rect(cornerRadius: Theme.Radius.card))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.top, Theme.Spacing.s)
        .accessibilityIdentifier("hostAwayBanner")
        .onAppear(perform: announce)
        .onChange(of: mayBeGone) { announce() }
    }

    // MARK: Full screen

    private var card: some View {
        VStack(spacing: Theme.Spacing.l) {
            VStack(spacing: Theme.Spacing.m) {
                icon(size: 44)
                title
                    .font(Theme.Typography.headline)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                message
                    .font(Theme.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            actions(compact: false)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: 420)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("hostAwayOverlay")
        .onAppear(perform: announce)
        .onChange(of: mayBeGone) { announce() }
    }

    // MARK: Parts

    @ViewBuilder private func icon(size: CGFloat) -> some View {
        Group {
            if mayBeGone || networkDenied {
                Image(systemName: networkDenied ? "wifi.exclamationmark" : "wifi.slash")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(Theme.accent)
            } else {
                ProgressView()
                    .controlSize(size > 30 ? .large : .regular)
                    .tint(Theme.accent)
            }
        }
        .accessibilityHidden(true)
    }

    private var title: Text { Text(titleResource) }
    private var message: Text { Text(messageResource) }

    private var titleResource: LocalizedStringResource {
        if mayBeGone {
            LocalizedStringResource("The host may be gone",
                                    comment: "Shown when the host's phone has been unreachable for about 2 minutes.")
        } else if let hostName {
            LocalizedStringResource("Waiting for \(hostName) to come back",
                                    comment: "Shown while the host's phone is away (app in the background or out of range). %@ is the host's name.")
        } else {
            LocalizedStringResource("Waiting for the host to come back",
                                    comment: "Shown while the host's phone is away, before the host's name is known.")
        }
    }

    private var messageResource: LocalizedStringResource {
        if networkDenied {
            LocalizedStringResource("Local Network access is off, so this phone can’t reach the game. Turn it on in Settings.",
                                    comment: "Host away: this app was denied Local Network access.")
        } else if mayBeGone {
            LocalizedStringResource("You can keep waiting, or leave the game. Your points so far stay in the standings.",
                                    comment: "Host away for a long time: what the player can do.")
        } else if presentation == .banner {
            LocalizedStringResource("Keep writing. The round goes on when the host is back.",
                                    comment: "Host away during writing: typing continues.")
        } else {
            LocalizedStringResource("The game picks up right where it left off.",
                                    comment: "Host away outside writing: nothing is lost.")
        }
    }

    @ViewBuilder private func actions(compact: Bool) -> some View {
        if networkDenied || mayBeGone {
            let layout = compact ? AnyLayout(HStackLayout(spacing: Theme.Spacing.s))
                                 : AnyLayout(VStackLayout(spacing: Theme.Spacing.s))
            layout {
                if networkDenied { OpenSettingsButton(compact: compact) }
                if mayBeGone {
                    Button(action: onLeave) {
                        Text("Leave game")
                    }
                    .modifier(OverlayButtonStyle(compact: compact, prominent: !networkDenied))
                    .accessibilityIdentifier("hostGoneLeaveButton")
                }
            }
        }
    }

    private func announce() {
        var text = String(localized: titleResource)
        if networkDenied || mayBeGone { text += ". " + String(localized: messageResource) }
        AccessibilityNotification.Announcement(text).post()
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
            if prominent {
                content.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            } else {
                content.buttonStyle(.bordered).buttonBorderShape(.capsule)
            }
        } else if prominent {
            content.buttonStyle(.primary)
        } else {
            content.buttonStyle(.secondary)
        }
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
