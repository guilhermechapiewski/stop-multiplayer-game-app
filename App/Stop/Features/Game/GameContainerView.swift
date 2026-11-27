import StopCore
import StopSession
import SwiftUI

/// The game screen: shows the view for the current phase (cross-fading between phases) under a toolbar
/// with the game menu.
struct GameContainerView: View {
    let model: AppModel

    var body: some View {
        if let client = model.client {
            GameScreen(client: client, banner: model.banners?.current, networkDenied: model.isLocalNetworkDenied,
                       onLeave: model.leaveGame)
                .id(ObjectIdentifier(client))
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
    /// The presence banner showing now ("Ana left the app").
    let banner: Banner?
    /// Local network access is off, so the host can't be reached.
    let networkDenied: Bool
    let onLeave: () -> Void

    init(client: any GameClient, banner: Banner? = nil, networkDenied: Bool = false, onLeave: @escaping () -> Void) {
        self.client = client
        self.banner = banner
        self.networkDenied = networkDenied
        self.onLeave = onLeave
    }

    @Environment(\.reduceMotion) private var reduceMotion
    @Environment(\.isPracticeGame) private var isPractice
    @State private var hostAwayGate = HostAwayGate()
    /// The round whose lock is being stamped "STOP!" over the screen.
    @State private var stampedRound: Round?
    @State private var toast: ToastItem?

    /// Longer under `-uiTesting`: on a busy test machine one accessibility snapshot can take over a second, and
    /// the tests check that the stamp shows up.
    private static let stampDuration: Duration =
        LaunchOptions(arguments: ProcessInfo.processInfo.arguments).uiTesting ? .seconds(4) : .seconds(1.6)
    private static let toastDuration: Duration = .seconds(3)

    private var stage: GameStage { GameStage(state: client.state, hostStatus: client.hostStatus) }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                content
                    .transition(.opacity)
                    .id(String(describing: stage))
                if hostAway == .fullScreen {
                    hostAwayOverlay(.fullScreen)
                        .transition(.opacity)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                // While writing it's a banner that pushes the form down, so typing carries on.
                if hostAway == .banner {
                    hostAwayOverlay(.banner)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: stage)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.3), value: hostAway)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.3),
                       value: client.hostStatus == .mayBeGone)
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
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                if let banner {
                    PresenceBannerView(banner: banner)
                        .id(banner.id)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
                if let toast {
                    ErrorToast(error: toast.error)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .onTapGesture { self.toast = nil }
                }
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35), value: banner)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.3), value: stampedRound?.number)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35), value: toast)
        .onChange(of: stage) { old, new in
            // The round just locked: stamp it, whether the host is still collecting or already scoring.
            if old == .writing, new == .collecting || new == .scoring {
                stampedRound = client.state?.currentRound
            }
            // Only the live countdown-to-writing transition, not a reconnect or relaunch into writing.
            if old == .countdown, new == .writing { GameFeedback.play(.writingStarted) }
        }
        .task(id: stampedRound?.number) {
            guard stampedRound != nil else { return }
            do { try await Task.sleep(for: Self.stampDuration) } catch { return }
            stampedRound = nil
        }
        .onChange(of: client.hostStatus, initial: true) { _, status in hostAwayGate.update(status) }
        .onChange(of: client.errorCount) {
            // A fresh item for every error (even a repeat of the last one), so it shows again and restarts the timer.
            if let error = client.lastError, ErrorToast.shows(error) { toast = ToastItem(error: error) }
        }
        .task(id: toast) {
            guard toast != nil else { return }
            do { try await Task.sleep(for: Self.toastDuration) } catch { return }
            toast = nil
        }
    }

    /// How the host-away overlay shows, if it does: never for the host itself (or in practice, where this phone
    /// is the host), nor once the game has ended.
    private var hostAway: HostAwayOverlay.Presentation? {
        guard !client.isHost, !isPractice, hostAwayGate.isShowing else { return nil }
        switch stage {
        case .ended, .gameOver: return nil
        case .writing: return .banner
        default: return .fullScreen
        }
    }

    private func hostAwayOverlay(_ presentation: HostAwayOverlay.Presentation) -> some View {
        let state = client.state
        return HostAwayOverlay(hostName: state.flatMap { $0.displayNames[$0.hostID] },
                               mayBeGone: client.hostStatus == .mayBeGone, networkDenied: networkDenied,
                               presentation: presentation, onLeave: onLeave)
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
            if let state { LobbyView(client: client, state: state, networkDenied: networkDenied) }
        case .revealing:
            if let state, let round { LetterRevealView(round: round, gameID: state.gameID) }
        case .countdown:
            if let state, let round, case .countdown(let seconds) = state.phase {
                CountdownView(round: round, gameID: state.gameID, secondsRemaining: seconds)
            }
        case .writing:
            if let state, let round { WritingView(client: client, state: state, round: round) }
        case .collecting:
            if let state, let round { CollectingView(client: client, state: state, round: round) }
        case .scoring:
            if let state, let round { ScoringView(client: client, state: state, round: round) }
        case .roundResults:
            if let state, let round { RoundResultsView(client: client, state: state, round: round) }
        case .gameOver:
            if let state { GameOverView(client: client, state: state, onClose: onLeave) }
        }
    }
}

/// One showing of the error toast.
struct ToastItem: Equatable {
    let id = UUID()
    let error: GameError
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
        case .unknownPlayer: "That player isn’t in this game."
        case .notParticipant: "You’ll play from the next round."
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
        StatusMessageView(icon: .progress, title: Text("Joining the game…"))
            .accessibilityIdentifier("joiningGame")
    }
}

/// The session ended without a game over (the app normally returns Home on its own; this covers the gap).
struct GameEndedView: View {
    let reason: EndReason
    let onClose: () -> Void

    var body: some View {
        let copy = EndReasonCopy(reason)
        StatusMessageView(icon: .symbol(copy.systemImage), title: Text(copy.title), message: Text(copy.message)) {
            Button("Back to Home", action: onClose)
                .buttonStyle(.primary)
                .accessibilityIdentifier("backHomeButton")
        }
    }
}

/// How a game that ended is explained: on the game screen and in Home's alert.
struct EndReasonCopy {
    let systemImage: String
    let title: LocalizedStringResource
    let message: LocalizedStringResource

    init(_ reason: EndReason) {
        switch reason {
        case .versionMismatch:
            systemImage = "arrow.down.app.fill"
            title = "Everyone needs the same app version"
            message = "Update the app on every phone from the App Store, then try again."
        case .removed:
            systemImage = "person.fill.xmark"
            title = "You were removed from the game"
            message = "The host removed you from the game."
        case .gameClosed:
            systemImage = "lock.fill"
            title = LocalizedStringResource("This game has already started",
                                            comment: "Alert title: the game can't be joined, it's past its lobby.")
            message = LocalizedStringResource(
                "New players can join only while the game is in the lobby.",
                comment: "Alert message: why a game that already started can't be joined.")
        case .gameOver, .leftGame:
            systemImage = "flag.checkered"
            title = "This game has ended"
            message = "The game is no longer available. Start or join another one."
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

#Preview("Game – host away") {
    let client = PreviewData.client(isHost: false, phase: .roundResults)
    client.hostStatus = .away
    return GameScreen(client: client, onLeave: {})
}

#Preview("Game – host may be gone while writing") {
    let client = PreviewData.client(isHost: false, phase: .writing)
    client.hostStatus = .mayBeGone
    return GameScreen(client: client, onLeave: {})
}
