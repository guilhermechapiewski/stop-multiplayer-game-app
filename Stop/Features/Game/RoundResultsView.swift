import StopCore
import StopSession
import SwiftUI

/// After a round: this round's ranking and the running totals. The host tunes the next round's rules and
/// picks Next round or End game; everyone else waits for the host.
struct RoundResultsView: View {
    let client: any GameClient
    let state: GameState
    let round: Round

    @Environment(\.reduceMotion) private var reduceMotion
    @Environment(\.isPracticeGame) private var isPractice
    @State private var confirmingEnd = false

    /// The host's way out: a practice game ends as a practice, not as a game for everyone.
    nonisolated static func endTitle(isPractice: Bool) -> LocalizedStringResource {
        isPractice ? "End practice" : "End game"
    }

    private var names: [PlayerID: String] { state.displayNames }
    private var hostName: String { names[state.hostID] ?? "" }
    private var roundStandings: [RankedEntry] {
        Standings.rank(Standings.roundPoints(round),
                       players: state.players.filter { round.participants.contains($0.id) })
    }
    private var totalStandings: [RankedEntry] { Standings.rank(state.totals, players: state.players) }
    private var activeCount: Int { state.activePlayers.count }
    private var stopsRequired: Int { max(1, min(state.settings.stopsRequired, activeCount)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Round \(round.number) · Letter \(round.letter)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                    Text("Round results")
                        .font(Theme.Typography.display)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.top, Theme.Spacing.s)

                StandingsCard(title: "This round", systemImage: "flag.checkered", entries: roundStandings,
                              names: names, me: client.localPlayerID, players: state.players,
                              highlightTop: false, identifier: "roundStandings")
                StandingsCard(title: "Total", systemImage: "trophy.fill", entries: totalStandings,
                              names: names, me: client.localPlayerID, players: state.players,
                              highlightTop: true, identifier: "totalStandings")
                if client.isHost { rulesCard }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.l)
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .alert(isPractice ? "End the practice?" : "End the game?", isPresented: $confirmingEnd) {
            Button(role: .destructive) { client.send(.endGame) } label: { Text(Self.endTitle(isPractice: isPractice)) }
                .accessibilityIdentifier("confirmEndGameButton")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(isPractice ? "You’ll see the final standings." : "Everyone sees the final standings.")
        }
    }

    // MARK: Host

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Label("Next round", systemImage: "slider.horizontal.3")
                .font(Theme.Typography.headline)
                .accessibilityAddTraits(.isHeader)
            Stepper(value: stopsBinding, in: 1...max(1, activeCount)) {
                LabeledContent("Stops to end a round") {
                    Text(stopsRequired, format: .number)
                        .font(Theme.Typography.headline)
                        .monospacedDigit()
                        .foregroundStyle(Color.primary)
                }
            }
            .accessibilityIdentifier("resultsStopsStepper")
            Divider()
            Toggle("Allow giving up", isOn: giveUpBinding)
                .accessibilityIdentifier("resultsAllowGiveUpToggle")
            Divider()
            SilentModeToggle(isOn: silentBinding, identifier: "resultsSilentModeToggle")
            Text(RulesText.footer(stopsRequired: stopsRequired, allowGiveUp: state.settings.allowGiveUp))
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
            Text(RulesText.scoring(silent: state.settings.silentScoring))
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .font(Theme.Typography.body)
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card))
    }

    private var stopsBinding: Binding<Int> {
        Binding(get: { stopsRequired }, set: { stops in
            client.send(.updateRoundSettings(stopsRequired: stops, allowGiveUp: state.settings.allowGiveUp,
                                             silentScoring: state.settings.silentScoring))
        })
    }

    private var giveUpBinding: Binding<Bool> {
        Binding(get: { state.settings.allowGiveUp }, set: { allow in
            client.send(.updateRoundSettings(stopsRequired: state.settings.stopsRequired, allowGiveUp: allow,
                                             silentScoring: state.settings.silentScoring))
        })
    }

    private var silentBinding: Binding<Bool> {
        Binding(get: { state.settings.silentScoring }, set: { silent in
            client.send(.updateRoundSettings(stopsRequired: state.settings.stopsRequired,
                                             allowGiveUp: state.settings.allowGiveUp, silentScoring: silent))
        })
    }

    /// Host only: reopens the round's last category, to correct a score before the next round starts.
    private var backToScoringButton: some View {
        Button {
            client.send(.previousCategory(round: round.number, category: state.settings.categories.count))
        } label: {
            Label("Back to scoring", systemImage: "arrow.uturn.backward")
        }
        .font(Theme.Typography.headline)
        .foregroundStyle(Theme.accent)
        .frame(minHeight: 44)
        .accessibilityHint(Text("Takes everyone back to the last category to correct a score."))
        .accessibilityIdentifier("backToScoringButton")
    }

    private var endGameButton: some View {
        Button { confirmingEnd = true } label: { Text(Self.endTitle(isPractice: isPractice)) }
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.accent)
            .frame(minHeight: 44)
            .accessibilityIdentifier("endGameButton")
    }

    @ViewBuilder private var bottomBar: some View {
        BottomActionBar {
            if client.isHost {
                Button { client.send(.nextRound) } label: {
                    Label("Next round", systemImage: "arrow.forward")
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier("nextRoundButton")
                // Side by side when they fit, stacked at large text sizes.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.l) { backToScoringButton; endGameButton }
                    VStack(spacing: Theme.Spacing.xs) { backToScoringButton; endGameButton }
                }
            } else {
                HStack(spacing: Theme.Spacing.s) {
                    ProgressView()
                        .accessibilityHidden(true)
                    Text("Waiting for \(hostName)…")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A ranked list: rank, name, points. Ties share a rank.
struct StandingsCard: View {
    let title: LocalizedStringKey
    let systemImage: String
    let entries: [RankedEntry]
    let names: [PlayerID: String]
    let me: PlayerID
    let players: [Player]
    /// Crowns the leaders.
    var highlightTop = false
    var identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Label(title, systemImage: systemImage)
                .font(Theme.Typography.headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.top, Theme.Spacing.m)
            VStack(spacing: 0) {
                ForEach(entries, id: \.playerID) { entry in
                    StandingRow(entry: entry, name: names[entry.playerID] ?? "", isMe: entry.playerID == me,
                                hasLeft: players.first { $0.id == entry.playerID }?.presence.isActive == false,
                                crowned: highlightTop && entry.rank == 1 && entry.points > 0)
                    if entry.playerID != entries.last?.playerID { Divider().padding(.leading, 64) }
                }
            }
            .padding(.bottom, Theme.Spacing.s)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

struct StandingRow: View {
    let entry: RankedEntry
    let name: String
    let isMe: Bool
    var hasLeft = false
    var crowned = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Rank and points on one line, the name wrapping freely below.
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack {
                        rank
                        Spacer(minLength: Theme.Spacing.s)
                        points
                    }
                    nameLine
                }
            } else {
                HStack(spacing: Theme.Spacing.m) {
                    rank
                    nameLine
                    Spacer(minLength: Theme.Spacing.s)
                    points
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.s + 2)
        .background(isMe ? Theme.accent.opacity(0.1) : .clear, in: .rect(cornerRadius: 14))
        .padding(.horizontal, Theme.Spacing.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Rank \(entry.rank), \(name)"))
        .accessibilityValue(Text(verbatim: AccessibilityText.score(entry.points)))
        .accessibilityIdentifier("standingRow")
    }

    private var rank: some View {
        Text(entry.rank, format: .number)
            .font(Theme.Typography.headline.monospacedDigit())
            .foregroundStyle(entry.rank == 1 ? Theme.accent : .secondary)
            .frame(minWidth: 28, alignment: .leading)
    }

    private var points: some View {
        Text("\(entry.points) pts")
            .font(Theme.Typography.headline.monospacedDigit())
    }

    /// "Gui (you) · left" as one Text, so it wraps as a sentence instead of splitting into columns, then the
    /// leader's crown. (The crown inside the Text, as an image glyph, was reported clipped by the accessibility
    /// audit.)
    private var nameLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            nameText
            if crowned {
                Image(systemName: "crown.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.crown)
                    .accessibilityHidden(true)
            }
        }
    }

    private var nameText: some View {
        var parts = [Text(verbatim: name).font(Theme.Typography.body.weight(isMe ? .bold : .semibold))]
        if isMe {
            parts.append(Text(verbatim: " "))
            parts.append(Text("(you)").font(Theme.Typography.caption).foregroundStyle(.secondary))
        }
        if hasLeft {
            parts.append(Text(verbatim: " "))
            parts.append(Text("· left").font(Theme.Typography.caption).foregroundStyle(.secondary))
        }
        return parts.dropFirst().reduce(parts[0]) { Text(TextJoin.pair($0, $1)) }
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Joins two styled `Text`s through interpolation (`Text + Text` is deprecated). The "%@%@" key is marked
/// not-for-translation in the string catalog.
private enum TextJoin {
    static func pair(_ first: Text, _ second: Text) -> LocalizedStringKey { "\(first)\(second)" }
}

@MainActor private func previewResultsClient(isHost: Bool) -> PreviewGameClient {
    let client = PreviewData.client(isHost: isHost, phase: .roundResults)
    var state = client.state!
    let ids = state.players.map(\.id)
    state.rounds[0].scores = Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
        (id, [10, index % 2 == 0 ? 5 : 10, 0, 10, 5, index == 1 ? 10 : 0])
    })
    client.state = state
    return client
}

#Preview("Round results – host") {
    let client = previewResultsClient(isHost: true)
    RoundResultsView(client: client, state: client.state!, round: client.state!.rounds[0])
        .background(Theme.background)
}

#Preview("Round results – guest") {
    let client = previewResultsClient(isHost: false)
    RoundResultsView(client: client, state: client.state!, round: client.state!.rounds[0])
        .background(Theme.background)
}
