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
    /// The round whose lock is being stamped "STOP!" over the screen.
    @State private var stampedRound: Round?
    @State private var toast: GameError?

    private static let stampDuration: Duration = .seconds(1.6)
    private static let toastDuration: Duration = .seconds(3)

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
        .overlay {
            if let stampedRound, let state = client.state {
                StopStampOverlay(state: state, round: stampedRound, viewer: client.localPlayerID)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if let toast {
                ErrorToast(error: toast)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .onTapGesture { self.toast = nil }
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.3), value: stampedRound?.number)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35), value: toast)
        .onChange(of: stage) { old, new in
            // The round just locked: stamp it, whether the host is still collecting or already scoring.
            if old == .writing, new == .collecting || new == .scoring {
                stampedRound = client.state?.currentRound
            }
        }
        .task(id: stampedRound?.number) {
            guard stampedRound != nil else { return }
            do { try await Task.sleep(for: Self.stampDuration) } catch { return }
            stampedRound = nil
        }
        .onChange(of: client.lastError) { _, error in
            if let error, ErrorToast.shows(error) { toast = error }
        }
        .task(id: toast) {
            guard toast != nil else { return }
            do { try await Task.sleep(for: Self.toastDuration) } catch { return }
            toast = nil
        }
    }

    private var showsMenu: Bool {
        switch stage {
        case .ended: false
        default: true
        }
    }

    @ViewBuilder private var content: some View {
        let state = client.state
        let round = state?.currentRound
        switch stage {
        case .connecting:
            ConnectingView()
        case .ended(let reason):
            GameEndedView(reason: reason, onClose: onLeave)
        case .lobby:
            if let state { LobbyView(client: client, state: state) }
        case .revealing:
            if let round { LetterRevealView(round: round) }
        case .countdown:
            if let round, case .countdown(let seconds)? = state?.phase {
                CountdownView(round: round, secondsRemaining: seconds)
            }
        case .writing:
            if let state, let round { WritingView(client: client, state: state, round: round) }
        case .collecting:
            if let state, let round { CollectingView(client: client, state: state, round: round) }
        case .scoring:
            ScoringPhaseView(client: client)
        case .roundResults:
            RoundResultsPhaseView(client: client)
        case .gameOver:
            GameOverPhaseView(client: client, onClose: onLeave)
        }
    }
}

/// A short-lived message for an action the host turned down.
struct ErrorToast: View {
    let error: GameError

    /// Races that sort themselves out (a STOP that arrived just after the lock, a score for a category that
    /// already moved on) aren't worth interrupting anyone for.
    static func shows(_ error: GameError) -> Bool {
        switch error {
        case .wrongPhase, .alreadyStopped, .staleRound: false
        default: true
        }
    }

    private var message: LocalizedStringResource {
        switch error {
        case .notHost: "Only the host can do that."
        case .gameClosed: "This game is closed."
        case .unknownPlayer, .notParticipant: "You’ll play from the next round."
        case .invalidSettings: "Those settings don’t work. Check the categories and stops."
        case .answersIncomplete: "Fill in every category to stop."
        case .giveUpNotAllowed: "Giving up isn’t allowed in this game."
        case .invalidScore: "Blank answers score 0."
        case .cannotScoreForOthers: "You can only score your own answers."
        case .notEnoughPlayers: "You need at least 2 players."
        case .wrongPhase, .alreadyStopped, .staleRound: "The game already moved on."
        }
    }

    var body: some View {
        Label {
            Text(message)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Theme.accent)
        }
        .font(Theme.Typography.caption)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s + 2)
        .background(.regularMaterial, in: .capsule)
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.top, Theme.Spacing.s)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("errorToast")
        .onAppear { AccessibilityNotification.Announcement(String(localized: message)).post() }
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
        case .removed: "The host removed you. Ask them to let you back in if it was a mistake."
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
