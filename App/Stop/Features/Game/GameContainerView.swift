import StopCore
import StopSession
import SwiftUI

/// The game screen: shows the view for the current phase (cross-fading between phases) under a toolbar
/// with the game menu.
struct GameContainerView: View {
    let model: AppModel

    var body: some View {
        if let client = model.client {
            GameScreen(client: client, onLeave: model.leaveGame)
        } else {
            Theme.background.ignoresSafeArea()
        }
    }
}

/// What the game screen is showing. Phases that tick (reveal, countdown, scoring) map to one stage each,
/// so only a change of phase cross-fades.
enum GameStage: Equatable {
    case connecting
    case ended(EndReason)
    case lobby, revealing, countdown, writing, collecting, scoring, roundResults, gameOver

    init(state: GameState?, hostStatus: HostStatus) {
        if let phase = state?.phase {
            switch phase {
            case .lobby: self = .lobby
            case .revealing: self = .revealing
            case .countdown: self = .countdown
            case .writing: self = .writing
            case .collecting: self = .collecting
            case .scoring: self = .scoring
            case .roundResults: self = .roundResults
            case .gameOver: self = .gameOver
            }
            // A session that ended for any other reason has no game left to show.
            if case .ended(let reason) = hostStatus, reason != .gameOver { self = .ended(reason) }
        } else if case .ended(let reason) = hostStatus {
            self = .ended(reason)
        } else {
            self = .connecting
        }
    }
}

struct GameScreen: View {
    let client: any GameClient
    let onLeave: () -> Void

    @Environment(\.reduceMotion) private var reduceMotion

    private var stage: GameStage { GameStage(state: client.state, hostStatus: client.hostStatus) }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                content
                    .transition(.opacity)
                    .id(String(describing: stage))
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: stage)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsMenu {
                    ToolbarItem(placement: .topBarTrailing) {
                        GameMenu(client: client, state: client.state, onLeave: onLeave)
                    }
                }
            }
        }
    }

    private var showsMenu: Bool {
        switch stage {
        case .ended: false
        default: true
        }
    }

    @ViewBuilder private var content: some View {
        switch stage {
        case .connecting:
            ConnectingView()
        case .ended(let reason):
            GameEndedView(reason: reason, onClose: onLeave)
        case .lobby:
            if let state = client.state { LobbyView(client: client, state: state) }
        case .revealing:
            RevealPhaseView(client: client)
        case .countdown:
            CountdownPhaseView(client: client)
        case .writing:
            WritingPhaseView(client: client)
        case .collecting:
            CollectingPhaseView(client: client)
        case .scoring:
            ScoringPhaseView(client: client)
        case .roundResults:
            RoundResultsPhaseView(client: client)
        case .gameOver:
            GameOverPhaseView(client: client, onClose: onLeave)
        }
    }
}

/// Joined, waiting for the host's first snapshot.
private struct ConnectingView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)
                .accessibilityHidden(true)
            Text("Joining the game…")
                .font(Theme.Typography.title)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .centeredScrolling()
        .accessibilityIdentifier("joiningGame")
    }
}

/// The session ended without a game over (the app normally returns Home on its own; this covers the gap).
struct GameEndedView: View {
    let reason: EndReason
    let onClose: () -> Void

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
                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Back to Home", action: onClose)
                .buttonStyle(.primary)
                .accessibilityIdentifier("backHomeButton")
        }
        .padding(.horizontal, Theme.Spacing.l)
        .centeredScrolling()
    }

    private var systemImage: String {
        switch reason {
        case .versionMismatch: "arrow.down.app.fill"
        case .removed: "person.fill.xmark"
        case .gameOver, .leftGame, .gameClosed: "flag.checkered"
        }
    }

    private var title: LocalizedStringKey {
        switch reason {
        case .versionMismatch: "Everyone needs the same app version"
        case .removed: "You were removed from the game"
        case .gameOver, .leftGame, .gameClosed: "This game has ended"
        }
    }

    private var message: LocalizedStringKey {
        switch reason {
        case .versionMismatch: "Update the app on every phone from the App Store, then try again."
        case .removed: "The host removed you from the game."
        case .gameOver, .leftGame, .gameClosed: "The game is no longer available. Start or join another one."
        }
    }
}

#Preview("Game – lobby") {
    GameScreen(client: PreviewData.client(isHost: true), onLeave: {})
}

#Preview("Game – connecting") {
    GameScreen(client: PreviewData.client(isHost: false, phase: nil), onLeave: {})
}

#Preview("Game – removed") {
    GameEndedView(reason: .removed, onClose: {})
}
