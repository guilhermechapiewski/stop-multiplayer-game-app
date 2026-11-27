import StopCore
import StopSession
import SwiftUI

// Stand-ins for the round screens. Task 15 replaces the reveal, countdown, writing and collecting views;
// Task 16 the scoring, round results and game over views. Each keeps its name and `client` input.

struct RevealPhaseView: View {
    let client: any GameClient

    var body: some View {
        PhasePlaceholder(title: "Picking a letter…", systemImage: "character.magnify",
                         detail: client.state?.currentRound.map { Text("Round \($0.number)") })
    }
}

struct CountdownPhaseView: View {
    let client: any GameClient

    var body: some View {
        PhasePlaceholder(title: "Get ready…", systemImage: "timer", detail: letter(client.state))
    }
}

struct WritingPhaseView: View {
    let client: any GameClient

    var body: some View {
        PhasePlaceholder(title: "Write your answers", systemImage: "pencil.and.list.clipboard",
                         detail: letter(client.state))
    }
}

struct CollectingPhaseView: View {
    let client: any GameClient

    var body: some View {
        PhasePlaceholder(title: "Collecting answers…", systemImage: "tray.and.arrow.down.fill", detail: nil)
    }
}

struct ScoringPhaseView: View {
    let client: any GameClient

    var body: some View {
        PhasePlaceholder(title: "Scoring", systemImage: "checklist", detail: letter(client.state))
    }
}

struct RoundResultsPhaseView: View {
    let client: any GameClient

    var body: some View {
        PhasePlaceholder(title: "Round results", systemImage: "list.number",
                         detail: client.state?.currentRound.map { Text("Round \($0.number)") })
    }
}

struct GameOverPhaseView: View {
    let client: any GameClient
    let onClose: () -> Void

    var body: some View {
        PhasePlaceholder(title: "Game over", systemImage: "trophy.fill", detail: nil) {
            Button("Back to Home", action: onClose)
                .buttonStyle(.primary)
                .accessibilityIdentifier("backHomeButton")
        }
    }
}

/// "Letter B" for the current round, if any.
private func letter(_ state: GameState?) -> Text? {
    state?.currentRound.map { Text("Letter \($0.letter)") }
}

/// A centred icon, title and optional detail line, with an optional action under them.
private struct PhasePlaceholder<Actions: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let detail: Text?
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.m) {
                Image(systemName: systemImage)
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Theme.Typography.title)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if let detail {
                    detail
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.secondary)
                }
            }
            actions
        }
        .padding(.horizontal, Theme.Spacing.l)
        .centeredScrolling()
    }
}

extension PhasePlaceholder where Actions == EmptyView {
    init(title: LocalizedStringKey, systemImage: String, detail: Text?) {
        self.init(title: title, systemImage: systemImage, detail: detail) { EmptyView() }
    }
}

#Preview("Writing placeholder") {
    WritingPhaseView(client: PreviewData.client(isHost: true, phase: .writing))
}
