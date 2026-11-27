import SwiftUI

/// What a `StatusMessageView` shows above its title.
enum StatusIcon {
    case symbol(String)
    case progress
}

/// A full-screen status: a symbol (or a spinner), a title, an optional explanation and optional actions,
/// centred and scrolling when Dynamic Type makes it tall.
struct StatusMessageView<Actions: View>: View {
    typealias Icon = StatusIcon

    let icon: Icon
    let title: Text
    var message: Text?
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.m) {
                switch icon {
                case .symbol(let name):
                    Image(systemName: name)
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                case .progress:
                    ProgressView()
                        .controlSize(.large)
                        .tint(Theme.accent)
                        .accessibilityHidden(true)
                }
                title
                    .font(Theme.Typography.title)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if let message {
                    message
                        .font(Theme.Typography.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            actions
        }
        .padding(.horizontal, Theme.Spacing.l)
        .centeredScrolling()
    }
}

extension StatusMessageView where Actions == EmptyView {
    init(icon: Icon, title: Text, message: Text? = nil) {
        self.init(icon: icon, title: title, message: message) { EmptyView() }
    }
}

/// Shown while an interrupted game is being resumed after a relaunch: a spinner, then (after about 2 minutes)
/// word that the host may be gone. With Local Network access off it points to Settings instead.
struct RejoiningView: View {
    let hostName: String
    var mayBeGone = false
    var networkDenied = false
    let onCancel: () -> Void

    var body: some View {
        StatusMessageView(icon: icon, title: title, message: message) {
            VStack(spacing: Theme.Spacing.s) {
                if networkDenied { OpenSettingsButton() }
                Button("Leave this game", action: onCancel)
                    .buttonStyle(.secondary)
                    .accessibilityHint("Stops reconnecting and goes back to the start screen.")
                    .accessibilityIdentifier("cancelRejoinButton")
            }
        }
        .background(Theme.background)
        .animation(.easeInOut(duration: 0.2), value: mayBeGone)
        .animation(.easeInOut(duration: 0.2), value: networkDenied)
        .onChange(of: mayBeGone) { _, gone in
            if gone { AccessibilityNotification.Announcement(String(localized: "The host may be gone")).post() }
        }
    }

    private var icon: StatusIcon {
        if networkDenied { .symbol("wifi.exclamationmark") } else if mayBeGone { .symbol("wifi.slash") } else { .progress }
    }

    private var title: Text {
        if networkDenied {
            Text("Allow Local Network access")
        } else if mayBeGone {
            Text("The host may be gone")
        } else if hostName.isEmpty {
            Text("Rejoining game…", comment: "Reconnecting to an interrupted game whose host's name isn't known.")
        } else {
            Text("Reconnecting to \(hostName)’s game…")
        }
    }

    private var message: Text {
        if networkDenied {
            Text("Local Network access is off, so this phone can’t reach the game. Turn it on in Settings.")
        } else if mayBeGone {
            Text("You can keep waiting, or leave the game. Your points so far stay in the standings.")
        } else {
            Text("Keep the app open. You’ll be back in the game as soon as the host’s phone is nearby.")
        }
    }
}

#Preview("Rejoining") {
    RejoiningView(hostName: "Ana") {}
}

#Preview("Rejoining – host may be gone") {
    RejoiningView(hostName: "Ana", mayBeGone: true) {}
}

#Preview("Rejoining – no local network") {
    RejoiningView(hostName: "Ana", networkDenied: true) {}
}
