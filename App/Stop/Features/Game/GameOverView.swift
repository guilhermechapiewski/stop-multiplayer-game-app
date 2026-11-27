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
        .background {
            if !winners.isEmpty {
                ConfettiView(isAnimated: !reduceMotion)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
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

    private var hero: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: winners.isEmpty ? "flag.checkered" : "trophy.fill")
                .font(.system(size: 88, weight: .bold))
                .foregroundStyle(winners.isEmpty ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.yellow.gradient))
                .shadow(color: .orange.opacity(0.35), radius: 16, y: 6)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.3)
                .rotationEffect(.degrees(appeared || reduceMotion ? 0 : -25))
                .accessibilityHidden(true)
            VStack(spacing: Theme.Spacing.xs) {
                Text("Game over")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(.secondary)
                title
                    .font(Theme.Typography.display)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("winnerTitle")
                if let points = standings.first?.points, !winners.isEmpty {
                    Text("\(points) points")
                        .font(Theme.Typography.headline.monospacedDigit())
                        .foregroundStyle(Theme.accent)
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

/// Confetti falling from the top for a few seconds; a still scatter with Reduce Motion.
struct ConfettiView: View {
    let isAnimated: Bool

    private struct Piece {
        let x: Double, delay: Double, speed: Double, spin: Double, sway: Double
        let size: CGSize, color: Color, isCircle: Bool
    }

    private static let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]
    private static let duration: Double = 4.5

    @State private var start = Date.now
    private let pieces: [Piece] = (0..<90).map { index in
        var rng = SplitMix(seed: UInt64(index) &* 0x9E3779B97F4A7C15)
        return Piece(x: rng.unit, delay: rng.unit * 1.2, speed: 0.55 + rng.unit * 0.5, spin: (rng.unit - 0.5) * 12,
                     sway: rng.unit * 2 * .pi, size: CGSize(width: 6 + rng.unit * 6, height: 9 + rng.unit * 8),
                     color: colors[index % colors.count], isCircle: index % 4 == 0)
    }

    /// The fall is over: stop redrawing.
    @State private var finished = false

    var body: some View {
        if !isAnimated {
            canvas(time: nil)
        } else if !finished {
            TimelineView(.animation) { context in
                canvas(time: context.date.timeIntervalSince(start))
            }
            .task {
                do { try await Task.sleep(for: .seconds(Self.duration)) } catch { return }
                finished = true
            }
        }
    }

    /// `time` nil draws the still version: pieces scattered across the top third.
    private func canvas(time: Double?) -> some View {
        Canvas { context, size in
            for piece in pieces {
                let progress: Double
                let opacity: Double
                if let time {
                    let t = max(0, time - piece.delay)
                    progress = t * piece.speed / 2.2
                    opacity = progress > 1 ? 0 : min(1, (Self.duration - time) / 0.8)
                    if t == 0 { continue }
                } else {
                    progress = piece.delay / 1.2 * 0.3
                    opacity = 0.9
                }
                guard opacity > 0 else { continue }
                let x = piece.x * size.width + sin(progress * 6 + piece.sway) * 18
                let y = -20 + progress * (size.height + 40)
                var pieceContext = context
                pieceContext.opacity = opacity
                pieceContext.translateBy(x: x, y: y)
                pieceContext.rotate(by: .radians(piece.spin * progress + piece.sway))
                let rect = CGRect(origin: CGPoint(x: -piece.size.width / 2, y: -piece.size.height / 2), size: piece.size)
                let path = piece.isCircle ? Path(ellipseIn: rect.insetBy(dx: 0, dy: (rect.height - rect.width) / 2))
                                          : Path(roundedRect: rect, cornerRadius: 2)
                pieceContext.fill(path, with: .color(piece.color))
            }
        }
    }
}

/// A tiny deterministic generator so the confetti looks the same on every render.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    var unit: Double { mutating get { Double(next() >> 11) / Double(1 << 53) } }
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
