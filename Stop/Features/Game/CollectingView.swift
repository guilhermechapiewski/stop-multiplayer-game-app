import StopCore
import StopSession
import SwiftUI

/// After the lock, while the host gathers everyone's answers. Usually over in a blink; when someone's phone is
/// slow or away, it shows who the game is waiting for and lets the host carry on without them.
struct CollectingView: View {
    let client: any GameClient
    let state: GameState
    let round: Round

    @Environment(\.reduceMotion) private var reduceMotion
    /// The host's "Continue anyway" appears only if someone's answers are still missing after a moment.
    @State private var delayPassed = false
    @State private var confirmingContinue = false

    private static let continueDelay: Duration = .seconds(2)

    private var names: [PlayerID: String] { state.displayNames }
    /// Participants still in the game, in join order.
    private var players: [Player] {
        state.players.filter { round.participants.contains($0.id) && $0.presence.isActive }
    }
    /// Snapshots keep everyone's answer key (with the answers hidden), so a key means "sent".
    private func hasSent(_ id: PlayerID) -> Bool { round.answers[id] != nil }
    private var missing: [Player] { players.filter { !hasSent($0.id) } }
    private var offersContinue: Bool { client.isHost && delayPassed && !missing.isEmpty }

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.m) {
                StopSign(size: 112)
                Text("Collecting answers…")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(round.forceEnded ? "The host ended the round." : "Round \(round.number) is over. Scoring starts in a moment.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 0) {
                ForEach(players, id: \.id) { player in
                    row(player)
                    if player.id != players.last?.id { Divider().overlay(Theme.divider).padding(.leading, 56) }
                }
            }
            .padding(.vertical, Theme.Spacing.s)
            .pieceCard()

            if offersContinue {
                VStack(spacing: Theme.Spacing.s) {
                    Button("Continue anyway") { confirmingContinue = true }
                        .buttonStyle(.secondary)
                        .accessibilityIdentifier("continueAnywayButton")
                    Text("Missing answers count as blank until they reconnect.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.l)
        .centeredScrolling()
        .animation(reduceMotion ? nil : .smooth, value: offersContinue)
        .alert(continueTitle, isPresented: $confirmingContinue) {
            Button("Continue anyway", role: .destructive) { client.send(.continueToScoring) }
                .accessibilityIdentifier("confirmContinueButton")
            Button("Keep waiting", role: .cancel) {}
        } message: {
            Text("Missing answers count as blank until they reconnect.")
        }
        .task {
            guard client.isHost else { return }
            do { try await Task.sleep(for: Self.continueDelay) } catch { return }
            delayPassed = true
        }
    }

    /// "Ana hasn't sent answers. Continue anyway?" (or several names).
    private var continueTitle: Text {
        let missingNames = missing.compactMap { names[$0.id] }
        let list = missingNames.formatted(.list(type: .and))
        return missingNames.count == 1 ? Text("\(list) hasn’t sent answers. Continue anyway?")
                                       : Text("\(list) haven’t sent answers. Continue anyway?")
    }

    private func row(_ player: Player) -> some View {
        let name = names[player.id] ?? player.name
        let away = player.presence == .away
        return HStack(spacing: Theme.Spacing.m) {
            PlayerInitial(name: name, dimmed: away, size: 32, isYou: player.id == client.localPlayerID)
            Text(verbatim: name)
                .font(Theme.Typography.body.weight(.bold))
                .foregroundStyle(Theme.text)
            Spacer(minLength: Theme.Spacing.s)
            if hasSent(player.id) {
                Label("Sent", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.teal)
            } else if away {
                Label("Reconnecting…", systemImage: "wifi.exclamationmark")
                    .foregroundStyle(Theme.secondaryText)
            } else {
                HStack(spacing: Theme.Spacing.xs) {
                    ProgressView().controlSize(.small)
                    Text("Sending…")
                }
                .foregroundStyle(Theme.secondaryText)
            }
        }
        .font(Theme.Typography.caption)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .accessibilityElement(children: .combine)
    }
}

/// The full-screen "STOP!" stamp shown the moment a round locks: the sign slams down on a yellow comic burst
/// over the sunburst (everything fades in with Reduce Motion), with who called it in a speech bubble.
struct StopStampOverlay: View {
    let state: GameState
    let round: Round
    let viewer: PlayerID

    @Environment(\.reduceMotion) private var reduceMotion
    @State private var stamped = false

    private var caption: Text {
        if round.forceEnded { return Text("The host ended the round") }
        if round.stops.map(\.playerID) == [viewer] { return Text("You called it!") }
        let names = state.displayNames
        let callers = round.stops.compactMap { stop in
            stop.playerID == viewer ? String(localized: "you") : names[stop.playerID]
        }
        return Text("Called by \(callers.formatted(.list(type: .and)))")
    }

    var body: some View {
        let burst = Starburst(points: 16, innerRatio: 0.74)
        ZStack {
            Theme.background.opacity(0.92)
                .ignoresSafeArea()
                .opacity(stamped ? 1 : 0)
            Sunburst(isAnimated: !reduceMotion, rays: 26, period: 18)
                .frame(width: 640, height: 640)
                .opacity(stamped ? 1 : 0)
            VStack(spacing: Theme.Spacing.l) {
                StopSign(size: 230)
                    .background {
                        burst.fill(Theme.yellow)
                            .overlay { burst.strokeBorder(Theme.ink, lineWidth: 4) }
                            .background { burst.fill(Theme.edge).offset(x: 4, y: 8) }
                            .frame(width: 300, height: 270)
                            .rotationEffect(.degrees(reduceMotion ? 0 : (stamped ? 6 : -30)))
                            .scaleEffect(reduceMotion ? 1 : (stamped ? 1 : 0.2))
                    }
                    .rotationEffect(.degrees(reduceMotion ? 0 : (stamped ? -8 : -20)))
                    .scaleEffect(reduceMotion ? 1 : (stamped ? 1 : 2.4))
                    .padding(.vertical, Theme.Spacing.m)
                caption
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.vertical, Theme.Spacing.s)
                    .padding(.top, 10)
                    .background {
                        let bubble = SpeechBubble(cornerRadius: 16, tailSize: 10, tailOnTop: true)
                        bubble.fill(Theme.edge).offset(x: 2, y: 3)
                        bubble.fill(Theme.surface)
                        bubble.strokeBorder(Theme.outline, lineWidth: Theme.Stroke.outline)
                    }
                    .padding(.horizontal, Theme.Spacing.l)
            }
            .opacity(stamped ? 1 : 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Stop!"))
        .accessibilityValue(caption)
        .accessibilityIdentifier("stopStamp")
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .spring(duration: 0.35, bounce: 0.3)) {
                stamped = true
            }
            GameFeedback.play(.roundLocked)
            AccessibilityNotification.Announcement(String(localized: "Stop!")).post()
        }
    }
}

#Preview("STOP! stamp") {
    let client = PreviewData.client(isHost: true, phase: .collecting)
    var state = client.state!
    state.rounds[0].stops = [StopRecord(playerID: PreviewData.guestID, kind: .stop)]
    return ZStack {
        Theme.background.ignoresSafeArea()
        StopStampOverlay(state: state, round: state.rounds[0], viewer: PreviewData.hostID)
    }
}

#Preview("Collecting – host") {
    let client = PreviewData.client(isHost: true, phase: .collecting)
    var state = client.state!
    state.rounds[0].stops = [StopRecord(playerID: PreviewData.guestID, kind: .stop)]
    state.rounds[0].answers = [PreviewData.guestID: [], PreviewData.hostID: ["Bruno"]]
    return CollectingView(client: client, state: state, round: state.rounds[0])
        .background(Theme.background)
}
