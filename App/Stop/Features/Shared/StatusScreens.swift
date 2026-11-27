import SwiftUI

/// Shown while an interrupted game is being resumed after a relaunch.
struct RejoiningView: View {
    let hostName: String
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.m) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.accent)
                    .accessibilityHidden(true)
                Text("Reconnecting to \(hostName)’s game…")
                    .font(Theme.Typography.title)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("Keep the app open. You’ll be back in the game as soon as the host’s phone is nearby.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Leave this game", action: onCancel)
                .buttonStyle(.secondary)
                .accessibilityHint("Stops reconnecting and goes back to the start screen.")
                .accessibilityIdentifier("cancelRejoinButton")
        }
        .padding(.horizontal, Theme.Spacing.l)
        .centeredScrolling()
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
        VStack(spacing: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.m) {
                Image(systemName: systemImage)
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Theme.Typography.title)
                    .accessibilityAddTraits(.isHeader)
                Text("Coming soon.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(.secondary)
            }
            Button(backTitle, action: onBack)
                .buttonStyle(.secondary)
                .accessibilityIdentifier("backButton")
        }
        .padding(.horizontal, Theme.Spacing.l)
        .centeredScrolling()
        .background(Theme.background)
    }
}

#Preview("Rejoining") {
    RejoiningView(hostName: "Ana") {}
}
