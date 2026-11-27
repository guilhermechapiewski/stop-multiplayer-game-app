import StopCore
import StopSession
import SwiftUI

/// Before the first round: who's here, the rules and the categories. The host can tune the rules and start.
struct LobbyView: View {
    let client: any GameClient
    let state: GameState

    @Environment(\.reduceMotion) private var reduceMotion

    private var names: [PlayerID: String] { state.displayNames }
    private var hostName: String { names[state.hostID] ?? "" }
    /// Players still in the game, in join order.
    private var players: [Player] { state.activePlayers }
    private var presentCount: Int { state.players.count(where: { $0.presence == .present }) }
    private var canStart: Bool { presentCount >= 2 }
    /// Stops required, capped by the players in the lobby (the engine applies the same cap each round).
    private var stopsRequired: Int { max(1, min(state.settings.stopsRequired, players.count)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header
                playersCard
                rulesCard
                categoriesCard
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.l)
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: state.players)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            (client.isHost ? Text("Your game") : Text("\(hostName)’s game"))
                .font(Theme.Typography.display)
                .accessibilityAddTraits(.isHeader)
            Text(client.isHost
                 ? "Friends nearby can join now from “Join a game”."
                 : "You’re in! The game starts when \(hostName) is ready.")
                .font(Theme.Typography.body)
                .foregroundStyle(.secondary)
        }
        .padding(.top, Theme.Spacing.s)
    }

    // MARK: Players

    private var playersCard: some View {
        LobbyCard(title: "Players (\(players.count))", systemImage: "person.2.fill") {
            FlowLayout(spacing: Theme.Spacing.s) {
                ForEach(players, id: \.id) { player in
                    PlayerChip(name: names[player.id] ?? player.name, presence: player.presence,
                               isHost: player.id == state.hostID, isYou: player.id == client.localPlayerID)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: Rules

    private var rulesCard: some View {
        LobbyCard(title: "Rules", systemImage: "list.bullet.clipboard.fill") {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                if client.isHost {
                    Stepper(value: stopsBinding, in: 1...max(1, players.count)) {
                        LabeledContent("Stops to end a round") {
                            Text(stopsRequired, format: .number)
                                .font(Theme.Typography.headline)
                                .monospacedDigit()
                                .foregroundStyle(Color.primary)
                        }
                    }
                    .accessibilityIdentifier("lobbyStopsStepper")
                    Divider()
                    Toggle("Allow giving up", isOn: giveUpBinding)
                        .accessibilityIdentifier("lobbyAllowGiveUpToggle")
                } else {
                    LabeledContent("Stops to end a round") {
                        Text(stopsRequired, format: .number).monospacedDigit()
                    }
                    Divider()
                    LabeledContent("Giving up") {
                        Text(state.settings.allowGiveUp ? "Allowed" : "Not allowed")
                    }
                }
                Text(RulesText.footer(stopsRequired: stopsRequired,
                                      allowGiveUp: state.settings.allowGiveUp))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            .font(Theme.Typography.body)
        }
    }

    private var stopsBinding: Binding<Int> {
        Binding(get: { stopsRequired }, set: { stops in
            client.send(.updateRoundSettings(stopsRequired: stops, allowGiveUp: state.settings.allowGiveUp))
        })
    }

    private var giveUpBinding: Binding<Bool> {
        Binding(get: { state.settings.allowGiveUp }, set: { allow in
            client.send(.updateRoundSettings(stopsRequired: state.settings.stopsRequired, allowGiveUp: allow))
        })
    }

    // MARK: Categories

    private var categoriesCard: some View {
        LobbyCard(title: "Categories (\(state.settings.categories.count))", systemImage: "square.grid.2x2.fill") {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ForEach(Array(state.settings.categories.enumerated()), id: \.offset) { index, category in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                        Text(index + 1, format: .number)
                            .font(Theme.Typography.caption.monospacedDigit())
                            .foregroundStyle(Theme.accent)
                            .frame(minWidth: 24, alignment: .trailing)
                        Text(verbatim: category)
                            .font(Theme.Typography.body)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: Start

    @ViewBuilder private var bottomBar: some View {
        BottomActionBar {
            if client.isHost {
                Button { client.send(.startGame) } label: {
                    Label("Start game", systemImage: "play.fill")
                }
                .buttonStyle(.primary)
                .disabled(!canStart)
                .accessibilityHint(canStart ? Text("Starts the first round for everyone.")
                                            : Text("Waiting for players…"))
                .accessibilityIdentifier("startGameButton")
                if !canStart {
                    Text("Waiting for players…")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            } else {
                HStack(spacing: Theme.Spacing.s) {
                    ProgressView()
                        .accessibilityHidden(true)
                    Text("Waiting for \(hostName) to start…")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A titled rounded card on the lobby's grouped background.
private struct LobbyCard<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Label(title, systemImage: systemImage)
                .font(Theme.Typography.headline)
                .foregroundStyle(Color.primary)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card))
    }
}

#Preview("Lobby – host") {
    let client = PreviewData.client(isHost: true)
    NavigationStack {
        LobbyView(client: client, state: client.state!)
    }
}

#Preview("Lobby – guest") {
    let client = PreviewData.client(isHost: false)
    NavigationStack {
        LobbyView(client: client, state: client.state!)
    }
}

#Preview("Lobby – host alone") {
    let client = PreviewData.client(isHost: true, playerNames: [])
    NavigationStack {
        LobbyView(client: client, state: client.state!)
    }
}
