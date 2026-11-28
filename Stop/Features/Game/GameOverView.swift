import StopCore
import StopSession
import SwiftUI

/// The end of the game: the winner (or co-winners) celebrated with confetti, the final standings, and the way
/// back Home.
struct GameOverView: View {
    let client: any GameClient
    let state: GameState
    let onClose: () -> Void

    @Environment(\.reduceMotion) private var reduceMotion
    @State private var appeared = false

    private var names: [PlayerID: String] { state.displayNames }
    private var standings: [RankedEntry] { Standings.rank(state.totals, players: state.players) }
    /// Everyone tied for first, if anyone scored at all.
    private var winners: [PlayerID] {
        standings.filter { $0.rank == 1 && $0.points > 0 }.map(\.playerID)
    }
    private var iWon: Bool { winners.contains(client.localPlayerID) }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                hero
                    .padding(.top, Theme.Spacing.l)
                StandingsCard(title: "Final standings", systemImage: "list.number", entries: standings,
                              names: names, me: client.localPlayerID, players: state.players,
                              highlightTop: true, identifier: "finalStandings")
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.l)
        }
        // Falling confetti rains over everything, then stops; the Reduce Motion scatter sits behind the content.
        .background {
            if !winners.isEmpty, reduceMotion { confetti }
        }
        .overlay {
            if !winners.isEmpty, !reduceMotion { confetti }
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button(action: onClose) {
                    Label("Back to Home", systemImage: "house.fill")
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier("backHomeButton")
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .spring(duration: 0.6, bounce: 0.45)) {
                appeared = true
            }
            if iWon { GameFeedback.play(.winner) }
        }
    }

    private var confetti: some View {
        ConfettiView(isAnimated: !reduceMotion)
            // Starts below the navigation bar, so it never covers the status bar or the menu button.
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var hero: some View {
        VStack(spacing: Theme.Spacing.m) {
            WinnerBadge(hasWinner: !winners.isEmpty)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.3)
                .rotationEffect(.degrees(appeared || reduceMotion ? 0 : -25))
            VStack(spacing: Theme.Spacing.xs) {
                Text("Game over")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.secondaryText)
                title
                    .font(Theme.Typography.display)
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("winnerTitle")
                if let points = standings.first?.points, !winners.isEmpty {
                    Text("\(points) points")
                        .font(Theme.Typography.headline.monospacedDigit().weight(.black))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, Theme.Spacing.m)
                        .padding(.vertical, Theme.Spacing.xs + 2)
                        .piece(Capsule(), fill: Theme.yellow, outline: Theme.ink, depth: 3)
                        .padding(.top, Theme.Spacing.xs)
                        .padding(.bottom, 3)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
        .opacity(appeared ? 1 : 0)
    }

    private var title: Text {
        let winnerNames = winners.compactMap { names[$0] }
        switch (winners.count, iWon) {
        case (0, _): return Text("Nobody scored this time")
        case (1, true): return Text("You won!")
        case (1, false): return Text("\(winnerNames[0]) wins!")
        case (_, true):
            let others = winners.filter { $0 != client.localPlayerID }.compactMap { names[$0] }
            return Text("You tie with \(others.formatted(.list(type: .and)))!")
        default: return Text("\(winnerNames.formatted(.list(type: .and))) tie!")
        }
    }
}

/// The trophy (or the chequered flag when nobody scored) on a round piece over the sunburst, which turns
/// slowly unless Reduce Motion is on. Decorative.
private struct WinnerBadge: View {
    let hasWinner: Bool

    @Environment(\.reduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    var body: some View {
        let side = 112 * min(scale, 1.3)
        Image(systemName: hasWinner ? "trophy.fill" : "flag.checkered")
            .font(.system(size: side * 0.5, weight: .bold))
            .foregroundStyle(hasWinner ? Theme.yellow : Theme.accent)
            .shadow(color: Theme.ink, radius: 0, x: 0, y: 3)
            .shadow(color: Theme.ink, radius: 0, x: 1.5, y: 0)
            .shadow(color: Theme.ink, radius: 0, x: -1.5, y: 0)
            .frame(width: side, height: side)
            .piece(Circle(), fill: Theme.surface, lineWidth: 3, depth: 6)
            .background {
                if hasWinner {
                    Sunburst(isAnimated: !reduceMotion, rays: 24, period: 30)
                        .frame(width: side * 2.6, height: side * 2.6)
                }
            }
            .padding(.vertical, Theme.Spacing.l)
            .accessibilityHidden(true)
    }
}

@MainActor private func previewGameOverClient(isHost: Bool, tie: Bool = false) -> PreviewGameClient {
    let client = PreviewData.client(isHost: isHost, phase: .gameOver)
    var state = client.state!
    let ids = state.players.map(\.id)
    state.rounds[0].scores = Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
        (id, [10, index == 1 && !tie ? 10 : 5, 0, 10, 5, 0])
    })
    client.state = state
    return client
}

#Preview("Game over – winner") {
    let client = previewGameOverClient(isHost: false)
    GameOverView(client: client, state: client.state!, onClose: {})
        .background(Theme.background)
}

#Preview("Game over – tie, reduce motion") {
    let client = previewGameOverClient(isHost: true, tie: true)
    GameOverView(client: client, state: client.state!, onClose: {})
        .background(Theme.background)
        .environment(\.reduceMotion, true)
}
