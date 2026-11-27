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
                StopSign(size: 96)
                Text("Collecting answers…")
                    .font(Theme.Typography.title)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(round.forceEnded ? "The host ended the round." : "Round \(round.number) is over. Scoring starts in a moment.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 0) {
                ForEach(players, id: \.id) { player in
                    row(player)
                    if player.id != players.last?.id { Divider().padding(.leading, 56) }
                }
            }
            .padding(.vertical, Theme.Spacing.s)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card))

            if offersContinue {
                VStack(spacing: Theme.Spacing.s) {
                    Button("Continue anyway") { confirmingContinue = true }
                        .buttonStyle(.secondary)
                        .accessibilityIdentifier("continueAnywayButton")
                    Text("Missing answers count as blank until they reconnect.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
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
                .font(Theme.Typography.body.weight(.semibold))
            Spacer(minLength: Theme.Spacing.s)
            if hasSent(player.id) {
                Label("Sent", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
            } else if away {
                Label("Reconnecting…", systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: Theme.Spacing.xs) {
                    ProgressView().controlSize(.small)
                    Text("Sending…")
                }
                .foregroundStyle(.secondary)
            }
        }
        .font(Theme.Typography.caption)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .accessibilityElement(children: .combine)
    }
}

/// The full-screen "STOP!" stamp shown the moment a round locks: the sign slams down (fades in with Reduce
/// Motion) with who called it.
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
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .opacity(stamped ? 1 : 0)
            VStack(spacing: Theme.Spacing.l) {
                StopSign(size: 240)
                    .rotationEffect(.degrees(reduceMotion ? 0 : (stamped ? -8 : -20)))
                    .scaleEffect(reduceMotion ? 1 : (stamped ? 1 : 2.4))
                caption
                    .font(Theme.Typography.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
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
