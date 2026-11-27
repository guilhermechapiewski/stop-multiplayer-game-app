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
        let copy = HostAwayCopy(hostName: hostName, mayBeGone: mayBeGone, networkDenied: networkDenied,
                                rejoining: true)
        StatusMessageView(icon: copy.systemImage.map(StatusIcon.symbol) ?? .progress, title: Text(copy.title),
                          message: Text(copy.message)) {
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
            if gone { AccessibilityNotification.Announcement(String(localized: copy.title)).post() }
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
