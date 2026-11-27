import SwiftUI

/// A full-screen status: a symbol (or a spinner), a title, an optional explanation and optional actions,
/// centred and scrolling when Dynamic Type makes it tall.
struct StatusMessageView<Actions: View>: View {
    enum Icon {
        case symbol(String)
        case progress
    }

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

/// Shown while an interrupted game is being resumed after a relaunch.
struct RejoiningView: View {
    let hostName: String
    let onCancel: () -> Void

    var body: some View {
        StatusMessageView(
            icon: .progress, title: Text("Reconnecting to \(hostName)’s game…"),
            message: Text("Keep the app open. You’ll be back in the game as soon as the host’s phone is nearby.")
        ) {
            Button("Leave this game", action: onCancel)
                .buttonStyle(.secondary)
                .accessibilityHint("Stops reconnecting and goes back to the start screen.")
                .accessibilityIdentifier("cancelRejoinButton")
        }
        .background(Theme.background)
    }
}

/// Placeholder for screens built in later tasks.
struct ComingSoonView: View {
    let title: LocalizedStringKey
    let systemImage: String
    var backTitle: LocalizedStringKey = "Back"
    let onBack: () -> Void

    var body: some View {
        StatusMessageView(icon: .symbol(systemImage), title: Text(title), message: Text("Coming soon.")) {
            Button(backTitle, action: onBack)
                .buttonStyle(.secondary)
                .accessibilityIdentifier("backButton")
        }
        .background(Theme.background)
    }
}

#Preview("Rejoining") {
    RejoiningView(hostName: "Ana") {}
}
